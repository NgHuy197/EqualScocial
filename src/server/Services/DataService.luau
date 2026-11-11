--!strict
--[[
	DataService — lưu / tải dữ liệu người chơi bằng ProfileStore (có KHÓA PHIÊN).

	  * Thư viện: Server/Vendor/ProfileStore (bản gốc của MAD STUDIO, xem SOURCE.txt; không sửa).
	  * Store: Config.Data.StoreName, key "u_<UserId>" (Config.Data.KeyPrefix).
	  * Khóa phiên: mỗi profile chỉ mở ở MỘT server. Người chơi vào server mới khi server cũ chưa nhả
	    khóa => ProfileStore nhờ server cũ lưu và nhả (MessagingService), chờ tối đa ~40 giây rồi giành
	    quyền. Nhờ vậy tiền khóa đấu giá / tài sản hiếm không thể bị nhân đôi khi đổi server.
	  * Phiên bị server khác lấy mất trong lúc đang chơi (OnSessionEnd) => gỡ dữ liệu và kick.
	  * Template + reconcile + sanitize: người chơi cũ tự được bổ sung trường mới, chặn số hỏng.
	  * Không mở được phiên => KICK (không bao giờ cho chơi bằng dữ liệu rỗng).
	  * Studio chưa bật API / chưa publish: ProfileStore tự dùng kho giả trong bộ nhớ (KHÔNG LƯU), warn.
	  * Lưu: ProfileStore autosave mỗi Config.Data.AutosaveSeconds, khi rời game (EndSession) và khi
	    tắt server (BindToClose của thư viện).

	API công khai giữ nguyên: Get / IsLoaded / OnLoaded / WaitForData.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(script.Parent.Parent.Util.Validate)

type PlayerData = Types.PlayerData

-- Phần API của ProfileStore mà service này dùng (thư viện không --!strict nên khai báo lại ở đây)
type Connection = { Disconnect: (self: Connection) -> () }
type Profile = {
	Data: PlayerData,
	EndSession: (self: Profile) -> (),
	AddUserId: (self: Profile, userId: number) -> (),
	OnSessionEnd: { Connect: (self: any, listener: () -> ()) -> Connection },
}
type Store = {
	StartSessionAsync: (self: Store, key: string, params: { Cancel: () -> boolean }) -> Profile?,
}
type ProfileStoreModule = {
	DataStoreState: string,
	New: (name: string, template: any) -> Store,
	SetConstant: (name: string, value: number) -> (),
}

type LoadedCallback = (player: Player, data: PlayerData) -> ()

local ProfileStore = (require(script.Parent.Parent.Vendor.ProfileStore) :: any) :: ProfileStoreModule

local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local listeners: { LoadedCallback } = {}
local warnedOffline = false
local store: Store? = nil

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
		Combat = { WindowStart = 0, Earned = 0 },
		Assets = {},
		Aura = { LastCycle = 0 },
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

	-- Cửa sổ trần tiền từ quái: số hỏng thì về mặc định (mở cửa sổ mới ở lần kiếm tiền kế)
	local combat = data.Combat
	if
		not Validate.isFiniteNumber(combat.WindowStart)
		or not Validate.isFiniteNumber(combat.Earned)
	then
		data.Combat = { WindowStart = 0, Earned = 0 }
	else
		combat.Earned = math.max(0, combat.Earned)
	end

	-- Tài sản thuê từ AURA: bỏ tài sản không còn trong Config, số hỏng thì đặt lại
	for assetId, record in data.Assets do
		if not Config.Assets[assetId] then
			data.Assets[assetId] = nil
		elseif
			not Validate.isFiniteNumber(record.LeasedAt)
			or not Validate.isFiniteNumber(record.Missed)
		then
			data.Assets[assetId] = { LeasedAt = os.time(), Missed = 0 }
		else
			record.Missed = math.max(0, math.floor(record.Missed))
		end
	end

	local aura = data.Aura
	if not Validate.isFiniteNumber(aura.LastCycle) then
		aura.LastCycle = 0
	end
	local escrow = aura.Escrow
	if escrow ~= nil then
		local valid = type(escrow) == "table"
			and type(escrow.AuctionId) == "string"
			and type(escrow.AssetId) == "string"
			and Validate.isFiniteNumber(escrow.Amount)
			and escrow.Amount > 0
		if not valid then
			aura.Escrow = nil
		end
	end
end

-- ───────────────────────────── Service ─────────────────────────────

local DataService = {}

function DataService:Init(_services: Types.Services)
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", Config.Data.AutosaveSeconds)
	-- ProfileStore.New không gọi DataStore ngay (chờ kiểm tra quyền API), nhưng vẫn bọc pcall để một
	-- lỗi bất ngờ không làm dừng boot: store = nil => _load sẽ kick người chơi.
	local ok, result = pcall(function()
		return ProfileStore.New(Config.Data.StoreName, buildTemplate())
	end)
	if ok then
		store = result
	else
		store = nil
		warn(`[DataService] Không tạo được ProfileStore: {tostring(result)}`)
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

function DataService:_load(player: Player)
	if profiles[player] or loading[player] then
		return
	end
	local profileStore = store
	if not profileStore then
		self:_failLoad(player, "ProfileStore không khả dụng")
		return
	end

	loading[player] = true
	local key = Config.Data.KeyPrefix .. tostring(player.UserId)
	-- Có thể yield lâu (chờ server khác nhả khóa). Người chơi thoát giữa chừng => thư viện tự hủy.
	local ok, result = pcall(function()
		return profileStore:StartSessionAsync(key, {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
	end)
	loading[player] = nil

	if not ok or result == nil then
		if player.Parent == Players then
			self:_failLoad(player, if ok then "không mở được phiên" else tostring(result))
		end
		return
	end
	local profile = result :: Profile

	-- Người chơi đã thoát trong lúc chờ: nhả khóa ngay, không đưa vào game
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId) -- gắn UserId với key (yêu cầu GDPR của Roblox)
	reconcile(profile.Data :: any, buildTemplate() :: any)
	sanitize(profile.Data)
	profile.Data.SchemaVersion = Config.Data.SchemaVersion

	-- Server khác giành phiên trong lúc người chơi còn ở đây: gỡ dữ liệu để không service nào sửa
	-- tiếp bản sẽ không được lưu, rồi kick.
	profile.OnSessionEnd:Connect(function()
		if profiles[player] == profile then
			profiles[player] = nil
			if player.Parent == Players then
				player:Kick(Config.Text.DataSessionEnded)
			end
		end
	end)

	if ProfileStore.DataStoreState ~= "Access" and not warnedOffline then
		warnedOffline = true
		warn(
			"[DataService] Studio không truy cập được DataStore -> chạy KHÔNG LƯU. "
				.. "Bật Game Settings > Security > 'Enable Studio Access to API Services' "
				.. "(và publish place) để test lưu/tải."
		)
	end

	profiles[player] = profile
	for _, callback in listeners do
		task.spawn(callback, player, profile.Data)
	end
end

-- Không mở được phiên: kick (không bao giờ cho chơi bằng dữ liệu rỗng rồi ghi đè dữ liệu thật).
-- Studio không có API thì ProfileStore đã tự dùng kho giả, nên tới được đây là lỗi thật cần xem.
function DataService:_failLoad(player: Player, reason: string)
	warn(
		`[DataService] Không tải được dữ liệu của {player.Name} ({player.UserId}): {reason} -> kick để tránh ghi đè.`
	)
	player:Kick(Config.Text.DataLoadFailed)
end

-- Người chơi rời game: gỡ khỏi bảng (service khác không còn truy cập được) rồi lưu lần cuối + nhả khóa
function DataService:_release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profiles[player] = nil
	profile:EndSession()
end

return DataService
