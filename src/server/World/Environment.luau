--!strict
--[[
	Environment.luau — ánh sáng, bầu khí quyển, mây và hiệu ứng hậu kỳ cho map dựng sẵn.

	Server đặt trạng thái ban đầu và bật attribute `DayNight` trên Lighting; client (Ambience) dựa vào đó
	để tự chạy chu kỳ ngày đêm theo giờ server (Calendar.GetClockTime). Map tự làm (đã có `World`) không
	gọi hàm này nên ánh sáng của map đó được giữ nguyên.

	Lighting.Technology không đặt được bằng script: giá trị "Future" nằm trong default.project.json.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Calendar = require(ReplicatedStorage.Shared.Calendar)
local Config = require(ReplicatedStorage.Shared.Config)

local Environment = {}

-- Lấy hiệu ứng có sẵn cùng lớp (template Studio thường có sẵn) hoặc tạo mới
local function ensure(parent: Instance, className: string): Instance
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Parent = parent
	return created
end

function Environment.Apply()
	local day = Config.Ambience.Day
	Lighting.ClockTime = Calendar.GetClockTime(Workspace:GetServerTimeNow())
	Lighting.GeographicLatitude = 32
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.Brightness = day.Brightness
	Lighting.Ambient = day.Ambient
	Lighting.OutdoorAmbient = day.OutdoorAmbient
	Lighting.ColorShift_Top = day.ColorShiftTop
	Lighting.ExposureCompensation = day.Exposure
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.5

	local atmosphere = ensure(Lighting, "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(204, 222, 240)
	atmosphere.Decay = Color3.fromRGB(120, 150, 190)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2

	local bloom = ensure(Lighting, "BloomEffect") :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 26
	bloom.Threshold = 1.3

	local color = ensure(Lighting, "ColorCorrectionEffect") :: ColorCorrectionEffect
	color.Brightness = 0.02
	color.Contrast = 0.08
	color.Saturation = 0.18
	color.TintColor = Color3.fromRGB(255, 250, 242)

	local rays = ensure(Lighting, "SunRaysEffect") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.6

	-- Template Studio có sẵn DepthOfField làm mờ xa: tắt để map nhìn rõ
	local depth = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if depth then
		depth.Enabled = false
	end

	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds = ensure(terrain, "Clouds") :: Clouds
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Color = Color3.fromRGB(255, 255, 255)
	end

	Lighting:SetAttribute(Config.Attributes.DayNight, true)
end

return Environment
