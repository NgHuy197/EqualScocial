--!strict
--[[
	BoardGui.luau — vẽ chữ lên mặt trước của bảng 3D bằng SurfaceGui (tạo nếu chưa có).
	Tách riêng để LeaderboardService không phụ thuộc cách dựng Instance (dễ test).
]]

local GUI_NAME = "ES_Board"
local LABEL_NAME = "Text"
local CANVAS_SIZE = Vector2.new(840, 480) -- tỉ lệ 1.75 khớp bảng 28 x 16 studs

local BoardGui = {}

local function findLabel(part: BasePart): TextLabel?
	local gui = part:FindFirstChild(GUI_NAME)
	local label = if gui then gui:FindFirstChild(LABEL_NAME) else nil
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

-- Ghi `text` lên bảng, tạo SurfaceGui + nhãn ở lần gọi đầu
local function createLabel(part: BasePart): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = GUI_NAME
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CANVAS_SIZE
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = LABEL_NAME
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
	label.TextColor3 = Color3.fromRGB(240, 243, 250)
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 30
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingTop = UDim.new(0, 16)
	padding.Parent = label
	return label
end

function BoardGui.Update(part: BasePart, text: string)
	local label = findLabel(part) or createLabel(part)
	label.Text = text
end

return BoardGui
