--!strict
--[[
	StationService — trạm miễn phí: Tắm, Giường, Ghế công viên.

	Instance có tag Config.Tags.Station và attribute StationId (trỏ tới Config.Stations) được gắn prompt.
	Hiệu ứng nằm trong Config.Stations[id].Effects, áp dụng qua StatsService.Modify.
	Hai lớp chặn:
	  * Util/Prompts: cooldown ngắn theo thời gian giữ phím (chặn exploit bỏ qua giữ phím).
	  * Cooldown cân bằng Config.Stations[id].Cooldown theo TỪNG người chơi, lưu trong
	    data.StationUsed (os.time()) nên thoát ra vào lại hay đổi server cũng không reset.
	    Đây là giới hạn chính cho tốc độ hồi Năng lượng / giảm Căng thẳng, tức là giới hạn thu nhập.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
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
		if type(station.Cooldown) ~= "number" or station.Cooldown < 0 then
			warn(`[StationService] Trạm '{stationId}' thiếu Cooldown hợp lệ`)
		end
	end
end

function StationService:Init(allServices: Types.Services)
	services = allServices
	validateConfig()
end

function StationService:Start()
	Prompts.BindTag(Config.Tags.Station, function(inst: Instance): Prompts.Spec?
		local rawId = inst:GetAttribute(Config.Attributes.Station)
		local station = if type(rawId) == "string" then Config.Stations[rawId] else nil
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
			-- Báo ngay khi bắt đầu giữ phím nếu trạm còn cooldown (đỡ phải giữ phím vô ích)
			OnHoldBegan = function(player: Player)
				local remaining = self:GetRemaining(player, rawId :: string)
				if remaining > 0 then
					self:_notifyCooldown(player, station, remaining)
				end
			end,
			OnTriggered = function(player: Player)
				self:_use(player, rawId :: string, station)
			end,
		}
	end)
end

-- Số giây còn phải chờ trước khi người chơi dùng lại trạm (0 = dùng được ngay)
function StationService:GetRemaining(player: Player, stationId: string): number
	local station = Config.Stations[stationId]
	local data = services.Data:Get(player)
	if not station or not data then
		return 0
	end
	local usedAt = data.StationUsed[stationId]
	if usedAt == nil then
		return 0
	end
	return math.max(0, usedAt + station.Cooldown - os.time())
end

function StationService:_notifyCooldown(player: Player, station: StationDef, remaining: number)
	services.Replication:Notify(
		player,
		string.format(Config.Text.StationCooldown, station.Name, Format.duration(remaining)),
		"warning"
	)
end

function StationService:_use(player: Player, stationId: string, station: StationDef)
	local data = services.Data:Get(player)
	if not data then
		return -- chưa có dữ liệu người chơi
	end
	-- Kiểm tra và ghi mốc thời gian liền nhau, không yield ở giữa
	local remaining = self:GetRemaining(player, stationId)
	if remaining > 0 then
		self:_notifyCooldown(player, station, remaining)
		return
	end
	if not services.Stats:Modify(player, station.Effects) then
		return
	end
	data.StationUsed[stationId] = os.time()
	services.Replication:Notify(player, station.DoneText, "success")
end

return StationService
