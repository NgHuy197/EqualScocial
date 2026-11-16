--!strict
--[[
	BoardGui.luau — vẽ chữ lên mặt trước của bảng 3D bằng SurfaceGui (tạo nếu chưa có).
	Tách riêng để LeaderboardService không phụ thuộc cách dựng Instance (dễ test).

	Dòng đầu của `text` là tiêu đề (chữ vàng, có vạch kẻ bên dưới), các dòng sau là nội dung.
]]

local GUI_NAME = "ES_Board"
local TITLE_NAME = "Title"
local BODY_NAME = "Text"
local CANVAS_SIZE = Vector2.new(840, 480) -- tỉ lệ 1.75 khớp bảng 28 x 16 studs
local BACKGROUND = Color3.fromRGB(20, 24, 36)
local GOLD = Color3.fromRGB(255, 205, 90)

local BoardGui = {}

local function findLabel(part: BasePart, name: string): TextLabel?
	local gui = part:FindFirstChild(GUI_NAME)
	local label = if gui then gui:FindFirstChild(name, true) else nil
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function newLabel(parent: Instance, name: string, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

-- Tạo SurfaceGui + nền + tiêu đề + phần nội dung ở lần gọi đầu
local function create(part: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = GUI_NAME
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CANVAS_SIZE
	gui.LightInfluence = 0.2 -- bảng điện tử: gần như tự sáng, ban đêm vẫn đọc được
	gui.Parent = part

	local frame = Instance.new("Frame")
	frame.Name = "Background"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = BACKGROUND
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 30)
	padding.PaddingRight = UDim.new(0, 30)
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.Parent = frame

	local title = newLabel(frame, TITLE_NAME, 40, GOLD)
	title.Size = UDim2.new(1, 0, 0, 46)

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.Position = UDim2.fromOffset(0, 52)
	rule.Size = UDim2.new(1, 0, 0, 3)
	rule.BackgroundColor3 = GOLD
	rule.BackgroundTransparency = 0.4
	rule.BorderSizePixel = 0
	rule.Parent = frame

	local body = newLabel(frame, BODY_NAME, 30, Color3.fromRGB(240, 243, 250))
	body.Position = UDim2.fromOffset(0, 66)
	body.Size = UDim2.new(1, 0, 1, -66)
	body.LineHeight = 1.08
end

-- Ghi `text` lên bảng
function BoardGui.Update(part: BasePart, text: string)
	if not part:FindFirstChild(GUI_NAME) then
		create(part)
	end
	local title = findLabel(part, TITLE_NAME)
	local body = findLabel(part, BODY_NAME)
	local firstBreak = string.find(text, "\n", 1, true)
	local head = if firstBreak then string.sub(text, 1, firstBreak - 1) else text
	local rest = if firstBreak then string.sub(text, firstBreak + 1) else ""
	-- Bỏ các dòng trống ngay sau tiêu đề
	rest = (string.gsub(rest, "^\n+", ""))
	if title then
		title.Text = head
	end
	if body then
		body.Text = rest
	end
end

return BoardGui
