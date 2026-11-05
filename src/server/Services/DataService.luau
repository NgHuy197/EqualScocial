--!strict
--[[
	DataService — lưu / tải dữ liệu người chơi bằng DataStoreService.

	  * Key: "u_<UserId>" (Config.Data.KeyPrefix)
	  * Template + reconcile: người chơi cũ tự được bổ sung trường mới khi game cập nhật.
	  * Tải: thử lại tối đa Config.Data.LoadRetries lần. Thất bại trên server thật => KICK người chơi
	    (tuyệt đối không cho chơi bằng dữ liệu rỗng, vì lần lưu sau sẽ ghi đè dữ liệu thật).
	  * Studio không bật "Enable Studio Access to API Services" (hoặc chưa publish place):
	    chạy ở chế độ KHÔNG LƯU và warn.
	  * Lưu: autosave mỗi Config.Data.AutosaveSeconds giây, khi rời game, và trong BindToClose.

	TODO (giai đoạn sau): chuyển sang ProfileStore (session locking). Hiện tại chưa có khoá phiên,
	nên nếu một người chơi ở hai server cùng lúc thì bản lưu sau cùng thắng. Khi chuyển, giữ nguyên API
	công khai của service này (Get / OnLoaded / WaitForData) để các service khác không phải sửa.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(script.Parent.Parent.Util.Validate)

type PlayerData = Types.PlayerData

type Profile = {
	Data: PlayerData,
	NoSave: boolean, -- true: chế độ Studio không có API, không ghi DataStore
	Saving: boolean, -- đang có một lần lưu chạy dở (tránh hai UpdateAsync chồng nhau)
}

type LoadedCallback = (player: Player, data: PlayerData) -> ()

local profiles: { [Player]: Profile } = {}
local listeners: { LoadedCallback } = {}
local pendingSaves = 0
local warnedOffline = false
local store: DataStore? = nil

-- ───────────────────────────── Tiện ích ─────────────────────────────

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value :: { [any]: any } do
		copy[key] = deepCopy(child)
	end
	return copy
end

-- Bổ sung các trường còn thiếu từ template vào dữ liệu đã lưu. KHÔNG xoá trường thừa
-- (ví dụ Owned là từ điển mở: mỗi itemId là một khoá).
local function reconcile(target: { [any]: any }, template: { [any]: any })
	for key, templateValue in template do
		local current = target[key]
		if current == nil or type(current) ~= type(templateValue) then
			-- Thiếu trường, hoặc sai kiểu (dữ liệu hỏng): lấy lại giá trị mặc định
			target[key] = deepCopy(templateValue)
		elseif type(templateValue) == "table" then
			-- Cả hai đều là bảng: bổ sung đệ quy các trường con còn thiếu
			reconcile(current, templateValue)
		end
	end
end

-- Dữ liệu của người chơi mới: GIỐNG NHAU cho tất cả (cùng tiền, cùng chỉ số, không gia thế)
local function buildTemplate(): PlayerData
	local skills: { [string]: Types.SkillRecord } = {}
	for _, skillId in Config.Skills.Order do
		skills[skillId] = { Level = Config.Skills.StartLevel, XP = 0 }
	end
	return {
		SchemaVersion = Config.Data.SchemaVersion,
		Money = Config.Economy.StartingMoney,
		Stats = deepCopy(Config.Stats.Start),
		Skills = skills,
		Owned = {},
	}
end

-- Chặn dữ liệu hỏng (NaN, âm, vượt khoảng) trước khi đưa vào game
local function sanitize(data: PlayerData)
	local money = data.Money
	if not Validate.isFiniteNumber(money) or money < 0 then
		data.Money = Config.Economy.StartingMoney
	else
		data.Money = math.min(math.floor(money), Config.Economy.MaxMoney)
	end

	for statId, startValue in Config.Stats.Start do
		local value = data.Stats[statId]
		if not Validate.isFiniteNumber(value) then
			data.Stats[statId] = startValue
		else
			data.Stats[statId] = math.clamp(value, Config.Stats.Min, Config.Stats.Max)
		end
	end

	for skillId, record in data.Skills do
		if not Validate.isFiniteNumber(record.Level) or not Validate.isFiniteNumber(record.XP) then
			data.Skills[skillId] = { Level = Config.Skills.StartLevel, XP = 0 }
		else
			record.Level = math.clamp(math.floor(record.Level), 0, Config.Skills.MaxLevel)
			record.XP = math.max(0, record.XP)
		end
	end
end

-- ───────────────────────────── Service ─────────────────────────────

local DataService = {}

function DataService:Init(_services: Types.Services)
	-- GetDataStore có thể ném lỗi ngay (ví dụ place chưa publish khi test trong Studio:
	-- "You must publish this place to the web to access DataStore"). Không để lỗi này làm dừng boot:
	-- store = nil, _fetch sẽ thất bại và _load xử lý (Studio: chạy không lưu; server thật: kick).
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		store = nil
		warn(`[DataService] Không tạo được DataStore: {tostring(result)}`)
	end
end

function DataService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(self._load, self, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self:_release(player)
	end)
	-- Người chơi đã vào trước khi Start chạy (thường gặp khi test trong Studio)
	for _, player in Players:GetPlayers() do
		task.spawn(self._load, self, player)
	end

	-- Autosave
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveSeconds)
			for player, profile in profiles do
				task.spawn(self._saveProfile, self, player.UserId, profile)
			end
		end
	end)

	-- Tắt server: lưu tất cả rồi chờ các lần lưu đang chạy (kể cả của người vừa rời)
	game:BindToClose(function()
		for player, profile in profiles do
			task.spawn(self._saveProfile, self, player.UserId, profile)
		end
		local deadline = os.clock() + Config.Data.ShutdownSaveTimeout
		while pendingSaves > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- ───────────────────────────── API công khai ─────────────────────────────

-- Dữ liệu của người chơi nếu đã tải xong, ngược lại nil. Dữ liệu được sửa trực tiếp (in-place).
function DataService:Get(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService:IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Đăng ký callback chạy khi dữ liệu một người chơi tải xong.
-- Cũng gọi ngay cho những người chơi ĐÃ tải xong trước thời điểm đăng ký.
function DataService:OnLoaded(callback: LoadedCallback)
	table.insert(listeners, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile.Data)
	end
end

-- Chờ (yield) tới khi dữ liệu sẵn sàng hoặc hết thời gian / người chơi thoát
function DataService:WaitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			return profile.Data
		end
		task.wait(0.1)
	end
	return nil
end

-- ───────────────────────────── Nội bộ ─────────────────────────────

-- Trả về (thành công, kết quả hoặc lỗi)
function DataService:_fetch(key: string): (boolean, any)
	local dataStore = store
	if not dataStore then
		return false, "DataStore không khả dụng" -- thử lại cũng vô ích: store đã nil từ Init
	end
	-- Studio: thử một lần là đủ (lỗi thường là chưa bật API, thử lại vô ích)
	local attempts = if RunService:IsStudio() then 1 else Config.Data.LoadRetries
	local lastError: any = nil
	for attempt = 1, attempts do
		local ok, result = pcall(function()
			return dataStore:GetAsync(key)
		end)
		if ok then
			return true, result
		end
		lastError = result
		warn(
			`[DataService] Tải {key} thất bại (lần {attempt}/{attempts}): {tostring(result)}`
		)
		if attempt < attempts then
			task.wait(Config.Data.LoadRetryDelay * attempt)
		end
	end
	return false, lastError
end

function DataService:_load(player: Player)
	if profiles[player] then
		return
	end
	local key = Config.Data.KeyPrefix .. tostring(player.UserId)
	local ok, result = self:_fetch(key)

	-- Người chơi có thể đã thoát trong lúc chờ DataStore
	if player.Parent ~= Players or profiles[player] then
		return
	end

	local data: PlayerData
	local noSave = false

	if ok and (result == nil or type(result) == "table") then
		if result == nil then
			data = buildTemplate() -- người chơi mới
		else
			data = result :: PlayerData
			reconcile(data :: any, buildTemplate() :: any)
		end
	elseif RunService:IsStudio() then
		-- Không có API access (hoặc place chưa publish): chạy thử không lưu, an toàn cho dữ liệu thật
		if not warnedOffline then
			warnedOffline = true
			warn(
				"[DataService] Studio không truy cập được DataStore -> chạy KHÔNG LƯU. "
					.. "Bật Game Settings > Security > 'Enable Studio Access to API Services' "
					.. "(và publish place) để test lưu/tải."
			)
		end
		data = buildTemplate()
		noSave = true
	else
		warn(
			`[DataService] Không tải được dữ liệu của {player.Name} ({player.UserId}) -> kick để tránh ghi đè.`
		)
		player:Kick(Config.Text.DataLoadFailed)
		return
	end

	sanitize(data)
	data.SchemaVersion = Config.Data.SchemaVersion

	profiles[player] = { Data = data, NoSave = noSave, Saving = false }
	for _, callback in listeners do
		task.spawn(callback, player, data)
	end
end

-- Lưu một profile. Bọc bộ đếm để BindToClose biết còn bao nhiêu lần lưu đang chạy.
function DataService:_saveProfile(userId: number, profile: Profile): boolean
	if profile.NoSave then
		return true
	end
	pendingSaves += 1
	local success = self:_doSave(userId, profile)
	pendingSaves -= 1
	return success
end

function DataService:_doSave(userId: number, profile: Profile): boolean
	local dataStore = store
	if not dataStore then
		warn("[DataService] Bỏ qua lưu: DataStore không khả dụng")
		return false
	end

	-- Chờ lần lưu trước (nếu có) xong để lần này mang dữ liệu mới nhất
	while profile.Saving do
		task.wait()
	end
	profile.Saving = true

	local key = Config.Data.KeyPrefix .. tostring(userId)
	local snapshot = deepCopy(profile.Data) -- sao chép để dữ liệu không đổi giữa chừng lúc serialize
	local success = false

	for attempt = 1, Config.Data.SaveRetries do
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function(_old: any)
				return snapshot
			end)
		end)
		if ok then
			success = true
			break
		end
		warn(
			`[DataService] Lưu {key} thất bại (lần {attempt}/{Config.Data.SaveRetries}): {tostring(
				err
			)}`
		)
		if attempt < Config.Data.SaveRetries then
			task.wait(Config.Data.SaveRetryDelay)
		end
	end

	profile.Saving = false
	return success
end

-- Người chơi rời game: gỡ profile khỏi bảng (service khác không còn truy cập được) rồi lưu lần cuối
function DataService:_release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profiles[player] = nil
	self:_saveProfile(player.UserId, profile)
end

return DataService
