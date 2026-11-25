--!strict
--[[
	Kit.luau — bộ dựng hình cơ bản cho thế giới (khối, nêm, trụ, cầu, biển chữ, nhãn nổi).

	Mọi công trình trong World/* đều dựng từ các hàm ở đây để map có một phong cách thống nhất
	(low-poly, màu phẳng, ít chi tiết thừa) và không cần asset ngoài: build ra là có map.

	Quy ước toạ độ: mỗi công trình có một CFrame gốc `base` đặt trên mặt đất, LookVector chỉ về MẶT TIỀN.
	`Kit.at(base, right, up, forward)` trả về CFrame lệch so với gốc theo ba trục dễ đọc đó.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Kit = {}

-- Bảng màu dùng chung của map
Kit.Palette = {
	Grass = Color3.fromRGB(104, 168, 88),
	GrassDark = Color3.fromRGB(78, 138, 72),
	Path = Color3.fromRGB(214, 198, 168),
	PathEdge = Color3.fromRGB(176, 160, 134),
	Plaza = Color3.fromRGB(226, 214, 190),
	Asphalt = Color3.fromRGB(86, 90, 100),
	Stone = Color3.fromRGB(150, 152, 160),
	StoneDark = Color3.fromRGB(104, 108, 118),
	Concrete = Color3.fromRGB(196, 196, 200),
	Wood = Color3.fromRGB(164, 116, 73),
	WoodDark = Color3.fromRGB(112, 78, 52),
	WoodLight = Color3.fromRGB(206, 164, 112),
	Metal = Color3.fromRGB(120, 128, 140),
	MetalDark = Color3.fromRGB(58, 62, 72),
	White = Color3.fromRGB(244, 244, 240),
	Cream = Color3.fromRGB(244, 230, 200),
	Glass = Color3.fromRGB(150, 205, 235),
	Water = Color3.fromRGB(84, 170, 220),
	Leaf = Color3.fromRGB(86, 160, 84),
	LeafLight = Color3.fromRGB(128, 190, 96),
	LeafDark = Color3.fromRGB(58, 122, 78),
	Trunk = Color3.fromRGB(120, 86, 58),
	Sand = Color3.fromRGB(226, 204, 152),
	RoofRed = Color3.fromRGB(196, 84, 68),
	RoofBrown = Color3.fromRGB(134, 88, 66),
	RoofBlue = Color3.fromRGB(70, 110, 160),
	RoofTeal = Color3.fromRGB(64, 150, 140),
	Lamp = Color3.fromRGB(255, 226, 160),
	Aura = Color3.fromRGB(140, 110, 255),
	AuraGlow = Color3.fromRGB(110, 230, 255),
	Night = Color3.fromRGB(26, 30, 46),
}

Kit.Fonts = {
	Regular = Enum.Font.SourceSans,
	Semibold = Enum.Font.SourceSansSemibold,
	Bold = Enum.Font.SourceSansBold,
}

-- CFrame lệch so với gốc công trình: sang phải / lên trên / ra phía trước (mặt tiền)
function Kit.at(base: CFrame, right: number, up: number, forward: number): CFrame
	return base * CFrame.new(right, up, -forward)
end

-- Gốc của một mặt tường: nằm sát mặt ngoài tường, LookVector hướng ra ngoài.
-- `width` là bề ngang (trục phải-trái), `depth` là bề sâu (trục trước-sau) của công trình.
function Kit.face(base: CFrame, width: number, depth: number, side: string): CFrame
	if side == "left" then
		return base * CFrame.new(-width / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	elseif side == "right" then
		return base * CFrame.new(width / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	elseif side == "back" then
		return base * CFrame.new(0, 0, depth / 2) * CFrame.Angles(0, math.pi, 0)
	end
	return base * CFrame.new(0, 0, -depth / 2)
end

local function setup(
	part: BasePart,
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
)
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
end

-- Khối hộp, `cf` là TÂM khối
function Kit.block(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	setup(part, parent, name, size, cf, color, material)
	return part
end

-- Nêm (mái dốc): cạnh thấp ở phía trước (-Z cục bộ), cạnh cao ở phía sau
function Kit.wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	local part = Instance.new("WedgePart")
	setup(part, parent, name, size, cf, color, material)
	return part
end

-- Trụ đứng: trục trụ trùng trục Y của `cf`, `cf` là tâm trụ
function Kit.cylinder(
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	setup(
		part,
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material
	)
	return part
end

function Kit.ball(
	parent: Instance,
	name: string,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	setup(part, parent, name, Vector3.new(diameter, diameter, diameter), cf, color, material)
	return part
end

-- Chi tiết trang trí: không va chạm, không đổ bóng (nhẹ cho vật lý và render)
function Kit.decor(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

-- Vùng tương tác vô hình: dùng làm điểm neo ProximityPrompt khi không có đồ vật nào hợp để gắn
function Kit.zone(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	local part = Kit.block(parent, name, size, cf, Color3.new(1, 1, 1))
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

-- Đèn điểm gắn vào một part (đèn đường do client bật/tắt theo giờ trong game qua tag Lamp)
function Kit.light(part: BasePart, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
	return light
end

export type SignOptions = {
	TextColor: Color3?,
	Background: Color3?, -- nil: nền trong suốt
	Font: Enum.Font?,
	PixelsPerStud: number?,
	Padding: number?, -- pixel
	LightInfluence: number?, -- 0: chữ tự sáng (biển đèn), 1: theo ánh sáng môi trường
}

-- Viết chữ lên một mặt của part (SurfaceGui, chữ tự co vừa khung)
function Kit.sign(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	options: SignOptions?
): TextLabel
	local opts: SignOptions = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PixelsPerStud or 40
	gui.LightInfluence = opts.LightInfluence or 1
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if opts.Background then 0 else 1
	label.BackgroundColor3 = opts.Background or Color3.new(0, 0, 0)
	label.BorderSizePixel = 0
	label.Font = opts.Font or Kit.Fonts.Bold
	label.Text = text
	label.TextColor3 = opts.TextColor or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = gui

	local pad = Instance.new("UIPadding")
	local amount = UDim.new(0, opts.Padding or 8)
	pad.PaddingTop = amount
	pad.PaddingBottom = amount
	pad.PaddingLeft = amount
	pad.PaddingRight = amount
	pad.Parent = label
	return label
end

-- Nhãn nổi phía trên một điểm tương tác: thẻ bo góc gồm tên + dòng gợi ý phím.
-- Kích thước tính bằng studs nên nhãn ở xa tự nhỏ lại, không che nhau; không hiện xuyên tường.
function Kit.label(part: BasePart, title: string, subtitle: string, heightAbove: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Adornee = part
	gui.Size = UDim2.fromScale(Config.World.LabelWidth, Config.World.LabelWidth * 0.21)
	gui.StudsOffsetWorldSpace = Vector3.new(0, heightAbove, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = Config.World.LabelMaxDistance
	gui.Parent = part

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Kit.Palette.Night
	card.BackgroundTransparency = 0.2
	card.BorderSizePixel = 0
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.22, 0)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.7
	stroke.Thickness = 1.5
	stroke.Parent = card

	local function line(text: string, font: Enum.Font, color: Color3, y: number, h: number)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.04, y)
		label.Size = UDim2.fromScale(0.92, h)
		label.Font = font
		label.Text = text
		label.TextColor3 = color
		label.TextScaled = true
		label.Parent = card
	end
	line(title, Kit.Fonts.Bold, Color3.new(1, 1, 1), 0.08, 0.5)
	line(subtitle, Kit.Fonts.Regular, Color3.fromRGB(200, 210, 230), 0.58, 0.34)
end

-- Folder con có tên
function Kit.folder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Model con có tên (gom các part của một công trình)
function Kit.model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

return Kit
