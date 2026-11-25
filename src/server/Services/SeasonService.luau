--!strict
--[[
	SeasonService — thông tin mùa cho HUD và thông báo khi người chơi vừa sang mùa mới.

	Việc sang mùa (lưu hồ sơ, trao danh hiệu, reset về vạch xuất phát) do DataService làm ngay lúc tải
	dữ liệu (Util/Season.Rollover). Service này chỉ:
	  * báo cho người chơi vừa sang mùa (toast chào mùa mới + danh hiệu nhận được);
	  * dựng phần Season trong snapshot (tên mùa, đếm ngược, thành tích PvP, danh hiệu mới nhất);
	  * trả lời GetProfile: hồ sơ của CHÍNH người gọi (danh hiệu, lịch sử mùa). Không có tham số nên
	    không cần kiểm tra kiểu; không gắn với vật thể trong map nên không kiểm tra khoảng cách.
	  * bắt kịp: ghi lúc người chơi vào mùa (SeasonJoinedAt) và cộng thời gian chơi; vào muộn so với
	    Config.Season.StartsAt thì được nhân XP (GetXPMultiplier) trong vài giờ chơi đầu.
	Mùa CHỈ đổi khi tăng Config.Season.Id; EndsAt chỉ để hiện đếm ngược.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validate = require(script.Parent.Parent.Util.Validate)

type PlayerData = Types.PlayerData

local GetProfile = Remotes.Function("GetProfile")
local GetPlayerProfile = Remotes.Function("GetPlayerProfile")

local services: Types.Services = {}
local profileLimiter =
	RateLimiter.new(Config.RateLimits.GetProfile.Calls, Config.RateLimits.GetProfile.Window)

local publicLimiter = RateLimiter.new(
	Config.RateLimits.GetPlayerProfile.Calls,
	Config.RateLimits.GetPlayerProfile.Window
)

local SeasonService = {}

function SeasonService:Init(allServices: Types.Services)
	services = allServices
	if Config.Season.Id < 1 or Config.Season.Id % 1 ~= 0 then
		warn(`[SeasonService] Config.Season.Id phải là số nguyên dương`)
	end
end

function SeasonService:Start()
	GetProfile.OnServerInvoke = function(player: Player)
		if not Validate.isPlayer(player) or not profileLimiter:Allow(player) then
			return nil
		end
		local ok, view = pcall(function()
			return self:GetProfile(player)
		end)
		if not ok then
			warn(`[SeasonService] Lỗi dựng hồ sơ: {tostring(view)}`)
			return nil
		end
		return view
	end

	-- Hồ sơ công khai của một người đang ở cùng máy chủ. Tham số từ client: kiểm tra kiểu, chỉ nhận
	-- UserId của người đang online (không đọc DataStore theo yêu cầu của client).
	GetPlayerProfile.OnServerInvoke = function(player: Player, userId: any)
		if not Validate.isPlayer(player) or not publicLimiter:Allow(player) then
			return nil
		end
		if not Validate.isFiniteNumber(userId) or userId % 1 ~= 0 then
			return nil
		end
		local target = Players:GetPlayerByUserId(userId)
		if not target then
			return nil
		end
		local ok, view = pcall(function()
			return self:GetPublicProfile(target)
		end)
		if not ok then
			warn(`[SeasonService] Lỗi dựng hồ sơ công khai: {tostring(view)}`)
			return nil
		end
		return view
	end

	-- Cộng thời gian chơi trong mùa cho người chơi online
	task.spawn(function()
		local tick = Config.Season.CatchUp.PlayTickSeconds
		while true do
			task.wait(tick)
			for _, player in Players:GetPlayers() do
				local data = services.Data:Get(player)
				if data then
					data.SeasonPlaySeconds += tick
				end
			end
		end
	end)

	services.Data:OnLoaded(function(player: Player, data: PlayerData)
		-- Lần đầu vào game trong mùa này (kể cả ngay sau khi sang mùa): ghi mốc vào mùa
		if data.SeasonJoinedAt == 0 then
			data.SeasonJoinedAt = os.time()
		end
		local boost = self:GetCatchUpBoost(data)
		if boost > 0 and self:GetBoostSecondsLeft(data) > 0 then
			services.Replication:Notify(
				player,
				string.format(
					Config.Text.CatchUpNotice,
					math.floor(boost * 100 + 0.5),
					Config.Season.CatchUp.PlayHours
				),
				"info"
			)
		end
		local record = services.Data:TakeRollover(player)
		if not record then
			return
		end
		services.Replication:Notify(
			player,
			string.format(Config.Text.SeasonRollover, Config.Season.Name, record.Name),
			"info"
		)
		for _, title in record.Titles do
			services.Replication:Notify(
				player,
				string.format(Config.Text.SeasonTitleEarned, title),
				"levelup"
			)
		end
	end)
end

-- Thưởng XP bắt kịp theo số tuần vào mùa muộn (0 nếu vào đúng lúc hoặc chưa ghi mốc)
function SeasonService:GetCatchUpBoost(data: PlayerData): number
	local catchUp = Config.Season.CatchUp
	if data.SeasonJoinedAt <= 0 then
		return 0
	end
	local weeksLate =
		math.floor(math.max(0, data.SeasonJoinedAt - Config.Season.StartsAt) / (7 * 86400))
	return math.min(catchUp.MaxBoost, catchUp.BoostPerWeek * weeksLate)
end

-- Số giây chơi còn được hưởng thưởng bắt kịp
function SeasonService:GetBoostSecondsLeft(data: PlayerData): number
	return math.max(0, Config.Season.CatchUp.PlayHours * 3600 - data.SeasonPlaySeconds)
end

-- Hệ số nhân XP hiện tại của người chơi (1 = không thưởng)
function SeasonService:GetXPMultiplier(player: Player): number
	local data = services.Data:Get(player)
	if not data or self:GetBoostSecondsLeft(data) <= 0 then
		return 1
	end
	return 1 + self:GetCatchUpBoost(data)
end

-- Hồ sơ đầy đủ của người chơi (bản sao, không đưa bảng dữ liệu thật ra ngoài)
function SeasonService:GetProfile(player: Player): Types.ProfileView?
	local data = services.Data:Get(player)
	if not data then
		return nil
	end
	local history: { Types.SeasonRecord } = {}
	for _, record in data.History do
		table.insert(history, table.clone(record))
	end
	return {
		SeasonName = Config.Season.Name,
		Pvp = self:BuildSnapshot(data).Pvp,
		PeakNetWorth = data.PeakNetWorth,
		Titles = table.clone(data.Titles),
		History = history,
		XPBoost = if self:GetBoostSecondsLeft(data) > 0 then self:GetCatchUpBoost(data) else 0,
		BoostSecondsLeft = self:GetBoostSecondsLeft(data),
		Cosmetics = services.Cosmetics:GetViews(player),
		EquippedTitle = data.Cosmetics.Title,
	}
end

-- Hồ sơ công khai: chỉ thứ người chơi muốn khoe (hạng, Nổi tiếng, PvP, danh hiệu, tài sản, đồ).
-- KHÔNG có tiền mặt, chỉ số, kỹ năng, lịch sử mùa hay tiến độ hướng dẫn.
function SeasonService:GetPublicProfile(target: Player): Types.PublicProfileView?
	local data = services.Data:Get(target)
	if not data then
		return nil
	end
	local assets: { string } = {}
	for assetId in data.Assets do
		local def = Config.Assets[assetId]
		if def then
			table.insert(assets, def.Name)
		end
	end
	table.sort(assets)
	local items: { string } = {}
	for _, shop in Config.Shops do
		for _, item in shop.Items do
			if item.Kind == "permanent" and data.Owned[item.Id] then
				table.insert(items, item.Name)
			end
		end
	end
	table.sort(items)
	return {
		UserId = target.UserId,
		Name = target.DisplayName,
		Fame = services.Shop:GetFame(target) + services.Assets:GetFame(target),
		NetWorth = services.Leaderboard:GetNetWorth(target),
		Rank = services.Leaderboard:GetRank(target),
		SeasonName = Config.Season.Name,
		Pvp = self:BuildSnapshot(data).Pvp,
		PeakNetWorth = data.PeakNetWorth,
		Titles = table.clone(data.Titles),
		EquippedTitle = data.Cosmetics.Title,
		Assets = assets,
		Items = items,
	}
end

-- Phần Season của snapshot gửi cho client
function SeasonService:BuildSnapshot(data: PlayerData): Types.SeasonSnapshot
	return {
		Name = Config.Season.Name,
		EndsAt = Config.Season.EndsAt,
		Pvp = {
			Rating = math.floor(data.Pvp.Rating + 0.5),
			Wins = data.Pvp.Wins,
			Losses = data.Pvp.Losses,
			Draws = data.Pvp.Draws,
		},
		Title = data.Titles[#data.Titles],
	}
end

return SeasonService
