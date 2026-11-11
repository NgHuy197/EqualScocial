--!strict
--[[
	SeasonService — thông tin mùa cho HUD và thông báo khi người chơi vừa sang mùa mới.

	Việc sang mùa (lưu hồ sơ, trao danh hiệu, reset về vạch xuất phát) do DataService làm ngay lúc tải
	dữ liệu (Util/Season.Rollover). Service này chỉ:
	  * báo cho người chơi vừa sang mùa (toast chào mùa mới + danh hiệu nhận được);
	  * dựng phần Season trong snapshot (tên mùa, đếm ngược, thành tích PvP, danh hiệu mới nhất);
	  * trả lời GetProfile: hồ sơ của CHÍNH người gọi (danh hiệu, lịch sử mùa). Không có tham số nên
	    không cần kiểm tra kiểu; không gắn với vật thể trong map nên không kiểm tra khoảng cách.
	Mùa CHỈ đổi khi tăng Config.Season.Id; EndsAt chỉ để hiện đếm ngược.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validate = require(script.Parent.Parent.Util.Validate)

type PlayerData = Types.PlayerData

local GetProfile = Remotes.Function("GetProfile")

local services: Types.Services = {}
local profileLimiter =
	RateLimiter.new(Config.RateLimits.GetProfile.Calls, Config.RateLimits.GetProfile.Window)

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

	services.Data:OnLoaded(function(player: Player)
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
