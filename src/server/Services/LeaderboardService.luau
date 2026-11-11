--!strict
--[[
	LeaderboardService — bảng xếp hạng tài sản ròng (tiền + giá các món vĩnh viễn đang sở hữu).

	  * Mỗi Config.Leaderboard.PublishSeconds giây (và khi rời game) ghi tài sản ròng của từng người chơi
	    vào OrderedDataStore "<StoreName>" (theo mùa, xem Config.Leaderboard.SeasonId).
	  * Mỗi RefreshSeconds giây đọc top TopCount, trộn với giá trị MỚI của người chơi đang ở server,
	    rồi cập nhật bảng 3D (tag Config.Tags.Leaderboard) và hạng hiển thị trên HUD.
	  * Không có DataStore xếp hạng (Studio chưa bật API / chưa publish) => bảng CỤC BỘ gồm người chơi
	    đang ở server, để vẫn test được; client được báo qua IsLocal.
	  * Nghi vấn gian lận: tài sản tăng hơn SuspiciousJump trong một chu kỳ ghi => chỉ ghi cảnh báo để xem xét.
	Tài sản ròng chỉ tính từ dữ liệu server; client không có đường nào để tự khai báo.
]]

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local BoardGui = require(script.Parent.Parent.Util.BoardGui)
local Prompts = require(script.Parent.Parent.Util.Prompts)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

type Entry = Types.LeaderboardEntry

local OpenLeaderboard = Remotes.Event("OpenLeaderboard")
local GetLeaderboard = Remotes.Function("GetLeaderboard")

local services: Types.Services = {}
local ordered: OrderedDataStore? = nil
local entries: { Entry } = {}
local rankByUserId: { [number]: number } = {}
local updatedAt = 0
local isLocal = true
local refreshing = false
local warnedRemote = false
local lastKnown: { [number]: number } = {} -- tài sản ròng gần nhất của mỗi người (kể cả đã rời)
local lastPublished: { [number]: number } = {}
local nameCache: { [number]: string } = {}
local limiter =
	RateLimiter.new(Config.RateLimits.GetLeaderboard.Calls, Config.RateLimits.GetLeaderboard.Window)

local LeaderboardService = {}

local function storeKey(userId: number): string
	return Config.Data.KeyPrefix .. tostring(userId)
end

local function parseKey(key: string): number?
	local digits = string.match(key, "^" .. Config.Data.KeyPrefix .. "(%d+)$")
	return if digits then tonumber(digits) else nil
end

local function warnRemoteOnce(err: any)
	if not warnedRemote then
		warnedRemote = true
		warn(
			`[Leaderboard] DataStore xếp hạng không khả dụng, dùng bảng cục bộ: {tostring(
				err
			)}`
		)
	end
end

local function resolveName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and type(name) == "string"
		then name
		else string.format(Config.Text.UnknownPlayer, userId)
	nameCache[userId] = resolved
	return resolved
end

function LeaderboardService:Init(allServices: Types.Services)
	services = allServices
	-- Giống DataService: GetOrderedDataStore có thể ném lỗi ngay khi place chưa publish
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Leaderboard.StoreName)
	end)
	if ok then
		ordered = result
	else
		ordered = nil
		warnRemoteOnce(result)
	end
end

function LeaderboardService:Start()
	Prompts.BindTag(Config.Tags.Leaderboard, function(_inst: Instance): Prompts.Spec?
		return {
			ActionText = Config.Text.LeaderboardPrompt,
			ObjectText = Config.Text.LeaderboardLabel,
			HoldDuration = 0,
			Cooldown = Config.Leaderboard.OpenCooldown,
			OnTriggered = function(player: Player)
				OpenLeaderboard:FireClient(player)
			end,
		}
	end)

	GetLeaderboard.OnServerInvoke = function(player: Player)
		if not limiter:Allow(player) then
			return nil
		end
		local ok, view = pcall(function()
			return self:GetView(player)
		end)
		if not ok then
			warn(`[Leaderboard] Lỗi dựng bảng xếp hạng: {tostring(view)}`)
			return nil
		end
		return view
	end

	-- Bảng 3D mới xuất hiện (ví dụ khi thay bằng map thật): vẽ ngay
	CollectionService:GetInstanceAddedSignal(Config.Tags.Leaderboard):Connect(function()
		self:_updateBoards()
	end)

	-- Có người chơi mới tải xong: ở chế độ cục bộ làm mới ngay (rẻ), chế độ DataStore đợi vòng làm mới
	services.Data:OnLoaded(function()
		if isLocal then
			self:_refresh()
		end
	end)

	-- Rời game: ghi lần cuối bằng giá trị đã biết (dữ liệu có thể đã bị DataService gỡ)
	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId
		local value = lastKnown[userId]
		if value then
			task.spawn(function()
				self:_publish(userId, value)
			end)
		end
	end)

	task.spawn(function()
		task.wait(2)
		while true do
			self:_refresh()
			task.wait(Config.Leaderboard.RefreshSeconds)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Leaderboard.PublishSeconds)
			for _, player in Players:GetPlayers() do
				if services.Data:Get(player) then
					self:_publish(player.UserId, self:GetNetWorth(player))
				end
			end
		end
	end)
end

-- ───────────────────────────── API công khai ─────────────────────────────

-- Tài sản ròng = tiền + giá các món vĩnh viễn đang sở hữu
function LeaderboardService:GetNetWorth(player: Player): number
	local data = services.Data:Get(player)
	if not data then
		return lastKnown[player.UserId] or 0
	end
	local value = data.Money
		+ services.Shop:GetOwnedValue(player)
		+ services.Assets:GetValue(player)
	lastKnown[player.UserId] = value
	-- Tài sản ròng cao nhất trong mùa (dùng cho hồ sơ và danh hiệu cuối mùa). Được tính lại mỗi lần
	-- gửi snapshot, nên luôn cập nhật khi tài sản thay đổi.
	if value > data.PeakNetWorth then
		data.PeakNetWorth = value
	end
	return value
end

-- Hạng hiện tại (nil nếu ngoài top)
function LeaderboardService:GetRank(player: Player): number?
	return rankByUserId[player.UserId]
end

function LeaderboardService:GetView(player: Player): Types.LeaderboardView
	return {
		Entries = entries,
		UpdatedAt = updatedAt,
		IsLocal = isLocal,
		SelfRank = rankByUserId[player.UserId],
		SelfNetWorth = self:GetNetWorth(player),
	}
end

-- ───────────────────────────── Nội bộ ─────────────────────────────

-- Ghi tài sản ròng lên OrderedDataStore (OrderedDataStore chỉ nhận số nguyên không âm)
function LeaderboardService:_publish(userId: number, netWorth: number)
	local store = ordered
	if not store then
		return
	end
	local previous = lastPublished[userId]
	if previous and netWorth - previous > Config.Leaderboard.SuspiciousJump then
		warn(
			`[Leaderboard] Nghi vấn: UserId {userId} tăng {Format.money(netWorth - previous)} trong một chu kỳ ghi (từ {Format.money(
				previous
			)} lên {Format.money(netWorth)})`
		)
	end
	local ok, err = pcall(function()
		store:SetAsync(storeKey(userId), math.max(0, math.floor(netWorth)))
	end)
	if ok then
		lastPublished[userId] = netWorth
	else
		warnRemoteOnce(err)
	end
end

function LeaderboardService:_refresh()
	if refreshing then
		return
	end
	refreshing = true
	local ok, err = pcall(function()
		self:_doRefresh()
	end)
	refreshing = false
	if not ok then
		warn(`[Leaderboard] Lỗi làm mới bảng xếp hạng: {tostring(err)}`)
	end
end

function LeaderboardService:_doRefresh()
	-- Giá trị MỚI của người chơi đang ở server (ghi đè giá trị đã ghi, vốn có thể cũ tới PublishSeconds)
	local merged: { [number]: number } = {}
	local names: { [number]: string } = {}
	for _, player in Players:GetPlayers() do
		if services.Data:Get(player) then
			merged[player.UserId] = self:GetNetWorth(player)
			names[player.UserId] = player.Name
			nameCache[player.UserId] = player.Name
		end
	end

	-- Phần đọc từ DataStore (người chơi đã rời hoặc ở server khác)
	local remote: { [number]: number } = {}
	local remoteOk = false
	local store = ordered
	if store then
		local success, page = pcall(function()
			return store:GetSortedAsync(false, Config.Leaderboard.TopCount):GetCurrentPage()
		end)
		if success then
			remoteOk = true
			for _, item in page do
				local userId = parseKey(item.key)
				if userId and type(item.value) == "number" then
					remote[userId] = item.value
				end
			end
		else
			warnRemoteOnce(page)
		end
	end
	for userId, value in remote do
		if merged[userId] == nil then
			merged[userId] = value
		end
	end

	local list: { Entry } = {}
	for userId, value in merged do
		table.insert(list, { Rank = 0, UserId = userId, Name = "", NetWorth = value })
	end
	table.sort(list, function(a: Entry, b: Entry)
		if a.NetWorth ~= b.NetWorth then
			return a.NetWorth > b.NetWorth
		end
		return a.UserId < b.UserId
	end)

	local top: { Entry } = {}
	local newRank: { [number]: number } = {}
	for index = 1, math.min(#list, Config.Leaderboard.TopCount) do
		local entry = list[index]
		entry.Rank = index
		entry.Name = names[entry.UserId] or resolveName(entry.UserId)
		table.insert(top, entry)
		newRank[entry.UserId] = index
	end

	-- Hạng đổi thì báo ReplicationService gửi lại snapshot cho người đó
	local previousRank = rankByUserId
	rankByUserId = newRank
	entries = top
	updatedAt = Workspace:GetServerTimeNow()
	isLocal = not remoteOk
	for _, player in Players:GetPlayers() do
		if previousRank[player.UserId] ~= newRank[player.UserId] then
			services.Replication:MarkDirty(player)
		end
	end

	self:_updateBoards()
end

-- Nội dung bảng 3D: tiêu đề + BoardRows hàng đầu (+ ghi chú nếu là bảng cục bộ)
function LeaderboardService:_boardText(): string
	local lines: { string } = { Config.Text.BoardTitle, "" }
	if #entries == 0 then
		table.insert(lines, Config.Text.BoardEmpty)
	end
	for index = 1, math.min(#entries, Config.Leaderboard.BoardRows) do
		local entry = entries[index]
		table.insert(
			lines,
			string.format(
				Config.Text.BoardRow,
				entry.Rank,
				entry.Name,
				Format.money(entry.NetWorth)
			)
		)
	end
	if isLocal then
		table.insert(lines, "")
		table.insert(lines, Config.Text.BoardLocalNote)
	end
	return table.concat(lines, "\n")
end

function LeaderboardService:_updateBoards()
	local text = self:_boardText()
	for _, inst in CollectionService:GetTagged(Config.Tags.Leaderboard) do
		local anchor = if inst:IsDescendantOf(Workspace) then Prompts.GetAnchor(inst) else nil
		if anchor then
			BoardGui.Update(anchor, text)
		end
	end
end

return LeaderboardService
