--!strict
--[[
	MonsterModel.luau — dựng model quái hoạt hình (quả cầu có mắt) và thanh máu nổi.

	Tách khỏi CombatService để logic chiến đấu không phụ thuộc cách dựng Instance (dễ test).
	Muốn thay bằng model đẹp hơn: sửa Build, giữ nguyên kiểu Handle trả về.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local EYE_COLOR = Color3.new(1, 1, 1)
local PUPIL_COLOR = Color3.fromRGB(30, 30, 40)
local HP_BACK_COLOR = Color3.fromRGB(20, 22, 30)
local HP_GOOD = Color3.fromRGB(76, 200, 120)
local HP_WARN = Color3.fromRGB(240, 190, 60)
local HP_BAD = Color3.fromRGB(235, 80, 80)

export type Handle = {
	Model: Model,
	Body: BasePart,
	Fill: Frame,
}

local MonsterModel = {}

local function newBall(name: string, diameter: number, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- Dựng quái đứng trên mặt đất tại `groundPosition`. Chưa gắn tag: CombatService tự gắn sau khi đăng ký.
function MonsterModel.Build(
	id: string,
	def: Config.MonsterDef,
	groundPosition: Vector3,
	parent: Instance
): Handle
	local model = Instance.new("Model")
	model.Name = def.Name

	-- Ball luôn là hình cầu nên lấy cạnh X làm đường kính
	local diameter = def.Size.X
	local body = newBall("Body", diameter, def.Color, model)
	body.CanCollide = true
	body.Position = groundPosition + Vector3.new(0, diameter / 2, 0)

	-- Mắt hướng về phía -Z (phía người chơi từ quảng trường đi tới)
	local eyeSize = diameter * 0.22
	for _, side in { -1, 1 } do
		local eyePosition = body.Position
			+ Vector3.new(side * diameter * 0.2, diameter * 0.12, -diameter * 0.42)
		local eye = newBall("Eye", eyeSize, EYE_COLOR, model)
		eye.Position = eyePosition
		local pupil = newBall("Pupil", eyeSize * 0.5, PUPIL_COLOR, model)
		pupil.Position = eyePosition + Vector3.new(0, 0, -eyeSize * 0.32)
	end

	-- Tên + thanh máu nổi phía trên quái
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = body
	gui.Size = UDim2.fromOffset(120, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, diameter / 2 + 1.6, 0)
	gui.MaxDistance = Config.World.LabelMaxDistance
	gui.Parent = body

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Font = Enum.Font.SourceSansBold
	nameLabel.Text = def.Name
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Parent = gui

	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 22)
	back.Size = UDim2.new(1, 0, 0, 9)
	back.BackgroundColor3 = HP_BACK_COLOR
	back.BorderSizePixel = 0
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HP_GOOD
	fill.BorderSizePixel = 0
	fill.Parent = back

	model.PrimaryPart = body
	model:SetAttribute(Config.Attributes.Monster, id)
	model.Parent = parent
	return { Model = model, Body = body, Fill = fill }
end

-- Cập nhật thanh máu theo tỉ lệ 0..1
function MonsterModel.SetHealth(handle: Handle, fraction: number)
	local clamped = math.clamp(fraction, 0, 1)
	handle.Fill.Size = UDim2.fromScale(clamped, 1)
	handle.Fill.BackgroundColor3 = if clamped > 0.5
		then HP_GOOD
		elseif clamped > 0.25 then HP_WARN
		else HP_BAD
end

return MonsterModel
