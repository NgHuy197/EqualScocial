--!strict
--[[
	SeasonService — thông tin mùa cho HUD và thông báo khi người chơi vừa sang mùa mới.

	Việc sang mùa (lưu hồ sơ, trao danh hiệu, reset về vạch xuất phát) do DataService làm ngay lúc tải
	dữ liệu (Util/Season.Rollover). Service này chỉ:
	  * báo cho người chơi vừa sang mùa (toast chào mùa mới + danh hiệu nhận được);
	  * dựng phần Season trong snapshot (tên mùa, đếm ngược, thành tích PvP, danh hiệu mới nhất).
	Mùa CHỈ đổi khi tăng Config.Season.Id; EndsAt chỉ để hiện đếm ngược.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type PlayerData = Types.PlayerData

local services: Types.Services = {}

local SeasonService = {}

function SeasonService:Init(allServices: Types.Services)
	services = allServices
	if Config.Season.Id < 1 or Config.Season.Id % 1 ~= 0 then
		warn(`[SeasonService] Config.Season.Id phải là số nguyên dương`)
	end
end

function SeasonService:Start()
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
