--!strict
--[[
	Ambience.luau — chu kỳ ngày đêm phía client (CHỈ hiển thị, không ảnh hưởng luật chơi).

	Giờ trời tính từ giờ server (Calendar.GetClockTime) nên mọi người chơi thấy cùng một bầu trời và
	trời sáng lại đúng lúc HUD sang ngày mới. Chỉ chạy khi server bật attribute DayNight trên Lighting
	(map dựng sẵn); map tự làm giữ nguyên ánh sáng của nó.

	Ban đêm: ánh sáng dịu hơn nhưng vẫn đủ nhìn, đèn đường (tag Lamp) bật sáng.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Calendar = require(ReplicatedStorage.Shared.Calendar)
local Config = require(ReplicatedStorage.Shared.Config)

local Ambience = {}

local lampsOn = false

-- 0 = ban ngày, 1 = đêm; chuyển dần trong TwilightHours quanh lúc mọc và lặn
local function nightFactor(clock: number): number
	local half = Config.Ambience.TwilightHours / 2
	local sunrise, sunset = Config.Calendar.SunriseHour, Config.Calendar.SunsetHour
	if clock >= sunrise + half and clock <= sunset - half then
		return 0
	elseif clock > sunset - half and clock < sunset + half then
		return (clock - (sunset - half)) / (half * 2)
	elseif clock > sunrise - half and clock < sunrise + half then
		return 1 - (clock - (sunrise - half)) / (half * 2)
	end
	return 1
end

local function setLamp(inst: Instance, on: boolean)
	if not inst:IsA("BasePart") then
		return
	end
	inst.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local light = inst:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = on
	end
end

local function apply()
	local clock = Calendar.GetClockTime(Workspace:GetServerTimeNow())
	local night = nightFactor(clock)
	local day, dark = Config.Ambience.Day, Config.Ambience.Night

	Lighting.ClockTime = clock
	Lighting.Brightness = day.Brightness + (dark.Brightness - day.Brightness) * night
	Lighting.Ambient = day.Ambient:Lerp(dark.Ambient, night)
	Lighting.OutdoorAmbient = day.OutdoorAmbient:Lerp(dark.OutdoorAmbient, night)
	Lighting.ColorShift_Top = day.ColorShiftTop:Lerp(dark.ColorShiftTop, night)
	Lighting.ExposureCompensation = day.Exposure + (dark.Exposure - day.Exposure) * night

	local shouldLight = night > 0.4
	if shouldLight ~= lampsOn then
		lampsOn = shouldLight
		for _, inst in CollectionService:GetTagged(Config.Tags.Lamp) do
			setLamp(inst, shouldLight)
		end
	end
end

function Ambience.Start()
	-- Đèn được tải về sau (streaming) cũng nhận đúng trạng thái hiện tại
	CollectionService:GetInstanceAddedSignal(Config.Tags.Lamp):Connect(function(inst: Instance)
		setLamp(inst, lampsOn)
	end)

	task.spawn(function()
		while true do
			if Lighting:GetAttribute(Config.Attributes.DayNight) == true then
				apply()
			end
			task.wait(Config.Ambience.UpdateSeconds)
		end
	end)
end

return Ambience
