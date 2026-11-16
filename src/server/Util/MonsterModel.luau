--!strict
--[[
	MonsterModel.luau — dựng model quái hoạt hình và thanh máu nổi.

	Tách khỏi CombatService để logic chiến đấu không phụ thuộc cách dựng Instance (dễ test).
	Mỗi loại quái có một kiểu dáng theo id (Slime Kẹo, Gấu Bông); id chưa có kiểu riêng dùng quả cầu
	có mắt. Muốn thay bằng model đẹp hơn: sửa các hàm dựng, giữ nguyên kiểu Handle trả về
	(`Body` là thân chính: CombatService đo khoảng cách và gắn prompt "Đánh" vào đó).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local EYE_COLOR = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(34, 30, 40)
local HP_BACK_COLOR = Color3.fromRGB(20, 22, 30)
local HP_GOOD = Color3.fromRGB(76, 200, 120)
local HP_WARN = Color3.fromRGB(240, 190, 60)
local HP_BAD = Color3.fromRGB(235, 80, 80)

export type Handle = {
	Model: Model,
	Body: BasePart,
	Fill: Frame,
}

-- Kết quả của một hàm dựng dáng: thân chính và độ cao đỉnh đầu so với tâm thân (để đặt thanh máu)
type Shape = {
	Body: BasePart,
	Top: number,
}

local MonsterModel = {}

local function setup(part: BasePart, name: string, color: Color3, cf: CFrame, parent: Instance)
	part.Name = name
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = cf
	part.Parent = parent
end

local function ball(
	parent: Instance,
	name: string,
	diameter: number,
	color: Color3,
	cf: CFrame
): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	setup(part, name, color, cf, parent)
	return part
end

local function block(parent: Instance, name: string, size: Vector3, color: Color3, cf: CFrame): Part
	local part = Instance.new("Part")
	part.Size = size
	setup(part, name, color, cf, parent)
	return part
end

-- Trụ có trục dọc theo trục Y của `cf`
local function cylinder(
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	color: Color3,
	cf: CFrame
): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	setup(part, name, color, cf * CFrame.Angles(0, 0, math.pi / 2), parent)
	return part
end

-- Hai mắt nhìn về -Z (phía người chơi từ thị trấn đi tới). `face` là tâm khuôn mặt, `spread` là
-- nửa khoảng cách hai mắt.
local function eyes(parent: Instance, face: CFrame, size: number, spread: number, button: boolean)
	for _, side in { -1, 1 } do
		local at = face * CFrame.new(side * spread, 0, 0)
		if button then
			ball(parent, "Eye", size, DARK, at)
			ball(
				parent,
				"EyeShine",
				size * 0.35,
				EYE_COLOR,
				at * CFrame.new(-size * 0.18, size * 0.2, -size * 0.36)
			)
		else
			ball(parent, "Eye", size, EYE_COLOR, at)
			ball(parent, "Pupil", size * 0.55, DARK, at * CFrame.new(0, 0, -size * 0.3))
		end
	end
end

-- Slime Kẹo: thân thạch trong, lõi sáng, má hồng và que kẹo trên đầu
local function buildSlime(model: Model, def: Config.MonsterDef, ground: Vector3): Shape
	local d = def.Size.X
	local center = CFrame.new(ground + Vector3.new(0, d * 0.46, 0))
	cylinder(
		model,
		"Puddle",
		d * 1.25,
		0.25,
		def.Color:Lerp(Color3.new(1, 1, 1), 0.25),
		CFrame.new(ground + Vector3.new(0, 0.13, 0))
	)

	local body = ball(model, "Body", d, def.Color, center)
	body.CanCollide = true
	body.CastShadow = true
	body.Transparency = 0.22
	body.Reflectance = 0.08
	local core = ball(
		model,
		"Core",
		d * 0.5,
		def.Color:Lerp(Color3.new(1, 1, 1), 0.55),
		center * CFrame.new(0, -d * 0.08, 0)
	)
	core.Material = Enum.Material.Neon

	local face = center * CFrame.new(0, d * 0.1, -d * 0.43)
	eyes(model, face, d * 0.2, d * 0.2, false)
	block(
		model,
		"Mouth",
		Vector3.new(d * 0.2, d * 0.05, d * 0.05),
		DARK,
		center * CFrame.new(0, -d * 0.1, -d * 0.49)
	)
	for _, side in { -1, 1 } do
		ball(
			model,
			"Cheek",
			d * 0.13,
			Color3.fromRGB(255, 170, 190),
			center * CFrame.new(side * d * 0.32, -d * 0.04, -d * 0.38)
		)
	end

	-- Que kẹo cắm trên đầu
	local stick = center * CFrame.new(d * 0.12, d * 0.62, 0) * CFrame.Angles(0, 0, math.rad(-14))
	cylinder(model, "CandyStick", d * 0.06, d * 0.5, Color3.fromRGB(250, 246, 236), stick)
	local candy = stick * CFrame.new(0, d * 0.34, 0)
	ball(model, "Candy", d * 0.34, Color3.fromRGB(255, 240, 120), candy)
	cylinder(model, "CandyBand", d * 0.36, d * 0.07, Color3.fromRGB(255, 110, 140), candy)
	return { Body = body, Top = d * 1.25 }
end

-- Gấu Bông: bụng, đầu, tai, mõm, tay chân và miếng vá trên bụng
local function buildBear(model: Model, def: Config.MonsterDef, ground: Vector3): Shape
	local d = def.Size.X
	local fur = def.Color
	local light = fur:Lerp(Color3.fromRGB(255, 236, 200), 0.6)
	local center = CFrame.new(ground + Vector3.new(0, d * 0.5, 0))

	local body = ball(model, "Body", d * 0.86, fur, center)
	body.CanCollide = true
	body.CastShadow = true
	cylinder(
		model,
		"Belly",
		d * 0.5,
		d * 0.06,
		light,
		center * CFrame.new(0, -d * 0.02, -d * 0.4) * CFrame.Angles(math.pi / 2, 0, 0)
	)
	block(
		model,
		"Patch",
		Vector3.new(d * 0.16, d * 0.16, d * 0.04),
		Color3.fromRGB(110, 150, 220),
		center * CFrame.new(d * 0.14, -d * 0.1, -d * 0.43) * CFrame.Angles(0, 0, math.rad(12))
	)

	local head = center * CFrame.new(0, d * 0.62, 0)
	ball(model, "Head", d * 0.62, fur, head).CastShadow = true
	for _, side in { -1, 1 } do
		local ear = head * CFrame.new(side * d * 0.25, d * 0.26, 0)
		ball(model, "Ear", d * 0.24, fur, ear)
		ball(model, "EarInner", d * 0.13, light, ear * CFrame.new(0, 0, -d * 0.07))
		-- Tay giơ ngang, chân duỗi ra trước
		ball(model, "Arm", d * 0.3, fur, center * CFrame.new(side * d * 0.47, d * 0.12, -d * 0.08))
		ball(
			model,
			"Leg",
			d * 0.34,
			fur,
			center * CFrame.new(side * d * 0.26, -d * 0.36, -d * 0.24)
		)
		ball(
			model,
			"Paw",
			d * 0.18,
			light,
			center * CFrame.new(side * d * 0.26, -d * 0.36, -d * 0.38)
		)
	end
	ball(model, "Snout", d * 0.28, light, head * CFrame.new(0, -d * 0.07, -d * 0.24))
	ball(model, "Nose", d * 0.1, DARK, head * CFrame.new(0, -d * 0.02, -d * 0.37))
	eyes(model, head * CFrame.new(0, d * 0.08, -d * 0.27), d * 0.09, d * 0.13, true)
	return { Body = body, Top = d * 1.08 }
end

-- Mặc định cho loại quái chưa có kiểu riêng: quả cầu có mắt
local function buildGeneric(model: Model, def: Config.MonsterDef, ground: Vector3): Shape
	local d = def.Size.X
	local center = CFrame.new(ground + Vector3.new(0, d / 2, 0))
	local body = ball(model, "Body", d, def.Color, center)
	body.CanCollide = true
	body.CastShadow = true
	eyes(model, center * CFrame.new(0, d * 0.12, -d * 0.42), d * 0.22, d * 0.2, false)
	return { Body = body, Top = d / 2 }
end

local SHAPES: { [string]: (model: Model, def: Config.MonsterDef, ground: Vector3) -> Shape } = {
	slime = buildSlime,
	bear = buildBear,
}

-- Dựng quái đứng trên mặt đất tại `groundPosition`. Chưa gắn tag: CombatService tự gắn sau khi đăng ký.
function MonsterModel.Build(
	id: string,
	def: Config.MonsterDef,
	groundPosition: Vector3,
	parent: Instance
): Handle
	local model = Instance.new("Model")
	model.Name = def.Name

	local builder: (model: Model, def: Config.MonsterDef, ground: Vector3) -> Shape = buildGeneric
	local custom = SHAPES[id]
	if custom then
		builder = custom
	end
	local shape = builder(model, def, groundPosition)
	local body = shape.Body

	-- Tên + thanh máu nổi phía trên quái
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = body
	gui.Size = UDim2.fromOffset(130, 38)
	gui.StudsOffsetWorldSpace = Vector3.new(0, shape.Top + 1.6, 0)
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
	back.Position = UDim2.fromOffset(0, 23)
	back.Size = UDim2.new(1, 0, 0, 11)
	back.BackgroundColor3 = HP_BACK_COLOR
	back.BorderSizePixel = 0
	back.Parent = gui
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(1, 0)
	backCorner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.5
	stroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HP_GOOD
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	-- Hàn mọi bộ phận vào thân: chỉ thân được neo, nên dời thân là cả con quái đi theo (MoveTo)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") and inst ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = inst
			weld.Parent = inst
			inst.Massless = true
			inst.Anchored = false
		end
	end

	model.PrimaryPart = body
	model:SetAttribute(Config.Attributes.Monster, id)
	model.Parent = parent
	return { Model = model, Body = body, Fill = fill }
end

-- Trượt quái tới `position` (tâm thân) trong `seconds` giây, quay mặt theo hướng đi
function MonsterModel.MoveTo(handle: Handle, position: Vector3, seconds: number)
	local body = handle.Body
	local delta = Vector3.new(position.X - body.Position.X, 0, position.Z - body.Position.Z)
	local goal = if delta.Magnitude > 0.05
		then CFrame.lookAt(position, position + delta)
		else CFrame.new(position) * body.CFrame.Rotation
	TweenService:Create(body, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { CFrame = goal })
		:Play()
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
