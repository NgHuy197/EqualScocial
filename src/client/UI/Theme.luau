--!strict
--[[
	Theme.luau — màu sắc, font và các hàm dựng UI dùng chung (toàn bộ UI dựng bằng code).

	Phong cách: thẻ tối bo góc, viền mảnh, màu nhấn xanh (hành động), tím (AURA), vàng (Nổi tiếng),
	xanh lá (tiền). Mọi cửa sổ gọi `Theme.chrome` để có cùng thanh tiêu đề, và `Theme.autoPolish` tự
	thêm viền + đổ bóng nhẹ cho mọi nút, nên UI mới thêm vào cũng đồng bộ.

	Font: họ Source Sans hiển thị tốt dấu tiếng Việt (Gotham/Arial có thể thiếu một số dấu).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(20, 24, 36),
	PanelLight = Color3.fromRGB(38, 44, 62),
	Header = Color3.fromRGB(30, 36, 54),
	Stroke = Color3.fromRGB(150, 170, 220),
	Text = Color3.fromRGB(240, 243, 250),
	TextMuted = Color3.fromRGB(160, 170, 192),
	Accent = Color3.fromRGB(74, 136, 244),
	Aura = Color3.fromRGB(160, 124, 250),
	Good = Color3.fromRGB(76, 204, 124),
	Warn = Color3.fromRGB(242, 192, 64),
	Bad = Color3.fromRGB(238, 84, 84),
	Money = Color3.fromRGB(120, 232, 152),
	Fame = Color3.fromRGB(255, 208, 96),
	Disabled = Color3.fromRGB(72, 78, 96),
	BarBackground = Color3.fromRGB(10, 12, 20),
}

Theme.Fonts = {
	Regular = Enum.Font.SourceSans,
	Semibold = Enum.Font.SourceSansSemibold,
	Bold = Enum.Font.SourceSansBold,
}

Theme.PanelTransparency = 0.06
Theme.HeaderHeight = 50

-- Màu viền toast theo loại thông báo (khớp Config.Notify.Kinds)
Theme.KindColors = {
	info = Theme.Colors.Accent,
	success = Theme.Colors.Good,
	warning = Theme.Colors.Warn,
	error = Theme.Colors.Bad,
	levelup = Theme.Colors.Fame,
	aura = Theme.Colors.Aura,
} :: { [string]: Color3 }

local POP_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

function Theme.corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

function Theme.padding(parent: Instance, amount: number): UIPadding
	local padding = Instance.new("UIPadding")
	local size = UDim.new(0, amount)
	padding.PaddingTop = size
	padding.PaddingBottom = size
	padding.PaddingLeft = size
	padding.PaddingRight = size
	padding.Parent = parent
	return padding
end

function Theme.stroke(parent: Instance, color: Color3?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Stroke
	stroke.Transparency = transparency or 0.72
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Theme.label(
	parent: Instance,
	text: string,
	textSize: number,
	color: Color3?,
	font: Enum.Font?
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font or Theme.Fonts.Regular
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = color or Theme.Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

-- Biến một Frame thành thẻ nền tối bo góc có viền mảnh
function Theme.panel(frame: GuiObject, radius: number?)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = Theme.PanelTransparency
	frame.BorderSizePixel = 0
	Theme.corner(frame, radius or 12)
	Theme.stroke(frame)
end

-- Khung chung của mọi cửa sổ: nền, viền, dải tiêu đề và nút Đóng cùng kiểu.
-- `title` và `closeButton` do cửa sổ tự tạo (đặt ở mép trên); hàm này chỉ trang trí.
function Theme.chrome(root: Frame, title: TextLabel, closeButton: TextButton, accent: Color3?)
	root.BackgroundColor3 = Theme.Colors.Panel
	root.BackgroundTransparency = 0.03
	root.BorderSizePixel = 0
	Theme.stroke(root, nil, 0.6)

	-- Dải tiêu đề: nằm DƯỚI chữ và nút (ZIndex 0) để không che nội dung
	local band = Instance.new("Frame")
	band.Name = "HeaderBand"
	band.ZIndex = 0
	band.Size = UDim2.new(1, 0, 0, Theme.HeaderHeight)
	band.BackgroundColor3 = Theme.Colors.Header
	band.BorderSizePixel = 0
	band.Parent = root
	Theme.corner(band, 12)
	-- Che hai góc bo phía dưới của dải để mép dưới thẳng
	local square = Instance.new("Frame")
	square.Name = "Square"
	square.ZIndex = 0
	square.AnchorPoint = Vector2.new(0, 1)
	square.Position = UDim2.fromScale(0, 1)
	square.Size = UDim2.new(1, 0, 0, 14)
	square.BackgroundColor3 = Theme.Colors.Header
	square.BorderSizePixel = 0
	square.Parent = band
	local line = Instance.new("Frame")
	line.Name = "AccentLine"
	line.ZIndex = 0
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.fromScale(0, 1)
	line.Size = UDim2.new(1, 0, 0, 2)
	line.BackgroundColor3 = accent or Theme.Colors.Accent
	line.BorderSizePixel = 0
	line.Parent = band

	title.TextSize = 24
	title.Position = UDim2.fromOffset(18, 8)

	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 9)
	closeButton.Size = UDim2.fromOffset(76, 32)
	closeButton.BackgroundColor3 = Theme.Colors.PanelLight
	closeButton.TextSize = 17
end

-- Hiện cửa sổ kèm hiệu ứng phóng nhẹ
function Theme.show(root: GuiObject)
	local scale = root:FindFirstChild("PopScale")
	if not scale or not scale:IsA("UIScale") then
		local created = Instance.new("UIScale")
		created.Name = "PopScale"
		created.Parent = root
		scale = created
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = 0.92
	root.Visible = true
	TweenService:Create(uiScale, POP_INFO, { Scale = 1 }):Play()
end

local function polishButton(button: TextButton)
	-- Nút trong suốt (chỉ có chữ, ví dụ tiêu đề bấm được) thì giữ nguyên
	if button.BackgroundTransparency >= 1 or button:FindFirstChild("PolishStroke") then
		return
	end
	local stroke = Theme.stroke(button, Color3.new(1, 1, 1), 0.82)
	stroke.Name = "PolishStroke"
	-- Chuyển sắc nhẹ từ trên xuống cho nút có khối (nhân với màu nền nên hợp mọi màu nút)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "PolishGradient"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 200, 214))
	gradient.Parent = button
	if not button:FindFirstChildOfClass("UICorner") then
		Theme.corner(button, 8)
	end
end

-- Tự trang trí mọi nút và thanh cuộn nằm trong `root`, kể cả phần được dựng sau này
function Theme.autoPolish(root: Instance, onClick: (() -> ())?)
	local function visit(inst: Instance)
		if inst:IsA("TextButton") then
			polishButton(inst)
			if onClick and not inst:GetAttribute("ClickHooked") then
				inst:SetAttribute("ClickHooked", true)
				inst.Activated:Connect(onClick)
			end
		elseif inst:IsA("ScrollingFrame") then
			inst.ScrollBarImageColor3 = Theme.Colors.Stroke
			inst.ScrollBarImageTransparency = 0.4
		end
	end
	for _, inst in root:GetDescendants() do
		visit(inst)
	end
	root.DescendantAdded:Connect(visit)
end

-- Màu thanh chỉ số: xanh khi tốt, vàng khi cần chú ý, đỏ khi nguy hiểm.
-- Chỉ số "đảo ngược" (Căng thẳng: càng cao càng xấu) được quy đổi trước khi so ngưỡng.
function Theme.statColor(value: number, inverted: boolean?): Color3
	local effective = if inverted then Config.Stats.Max - value else value
	if effective >= Config.UI.StatGood then
		return Theme.Colors.Good
	elseif effective >= Config.UI.StatWarn then
		return Theme.Colors.Warn
	end
	return Theme.Colors.Bad
end

return Theme
