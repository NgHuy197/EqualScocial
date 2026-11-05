--!strict
--[[
	StationService — trạm miễn phí: Tắm, Giường, Ghế công viên.

	Instance có tag Config.Tags.Station và attribute StationId (trỏ tới Config.Stations) được gắn prompt.
	Hiệu ứng nằm trong Config.Stations[id].Effects, áp dụng qua StatsService.Modify.
	Cooldown phía server do Util/Prompts áp dụng, nên không thể spam trạm nhanh hơn thời gian giữ phím.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Prompts = require(script.Parent.Parent.Util.Prompts)

type StationDef = Config.StationDef

local services: Types.Services = {}

local StationService = {}

local function validateConfig()
	for stationId, station in Config.Stations do
		for statId in station.Effects do
			if not Config.Stats.Defs[statId] then
				warn(
					`[StationService] Trạm '{stationId}' có hiệu ứng cho chỉ số không tồn tại: {statId}`
				)
			end
		end
	end
end

function StationService:Init(allServices: Types.Services)
	services = allServices
	validateConfig()
end

function StationService:Start()
	Prompts.BindTag(Config.Tags.Station, function(inst: Instance): Prompts.Spec?
		local stationId = inst:GetAttribute(Config.Attributes.Station)
		local station = if type(stationId) == "string" then Config.Stations[stationId] else nil
		if not station then
			warn(
				`[StationService] {inst:GetFullName()} có tag Station nhưng attribute {Config.Attributes.Station} không hợp lệ`
			)
			return nil
		end
		return {
			ActionText = station.ActionText,
			ObjectText = station.Name,
			HoldDuration = station.HoldDuration,
			OnTriggered = function(player: Player)
				self:_use(player, station)
			end,
		}
	end)
end

function StationService:_use(player: Player, station: StationDef)
	if not services.Stats:Modify(player, station.Effects) then
		return -- chưa có dữ liệu người chơi
	end
	services.Replication:Notify(player, station.DoneText, "success")
end

return StationService
