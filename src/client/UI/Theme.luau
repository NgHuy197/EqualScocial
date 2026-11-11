--!strict
--[[
	Theme.luau — màu sắc, font và vài hàm dựng UI dùng chung (toàn bộ UI dựng bằng code).

	Font: họ Source Sans hiển thị tốt dấu tiếng Việt (Gotham/Arial có thể thiếu một số dấu).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(24, 28, 38),
	PanelLight = Color3.fromRGB(40, 46, 60),
	Text = Color3.fromRGB(240, 243, 250),
	TextMuted = Color3.fromRGB(165, 172, 190),
	Accent = Color3.fromRGB(80, 140, 240),
	Good = Color3.fromRGB(76, 200, 120),
	Warn = Color3.fromRGB(240, 190, 60),
	Bad = Color3.fromRGB(235, 80, 80),
	Money = Color3.fromRGB(120, 230, 150),
	Fame = Color3.fromRGB(255, 205, 90),
	Disabled = Color3.fromRGB(78, 84, 100),
	BarBackground = Color3.fromRGB(12, 14, 20),
}

Theme.Fonts = {
	Regular = Enum.Font.SourceSans,
	Semibold = Enum.Font.SourceSansSemibold,
	Bold = Enum.Font.SourceSansBold,
}

-- Màu viền toast theo loại thông báo (khớp Config.Notify.Kinds)
Theme.KindColors = {
	info = Theme.Colors.Accent,
	success = Theme.Colors.Good,
	warning = Theme.Colors.Warn,
	error = Theme.Colors.Bad,
	levelup = Theme.Colors.Fame,
	aura = Color3.fromRGB(160, 120, 240),
} :: { [string]: Color3 }

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
