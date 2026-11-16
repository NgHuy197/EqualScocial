--!strict
--[[
	NameTag.luau — bảng tên trên đầu nhân vật (BillboardGui dựng phía server, tự replicate cho mọi người).

	Dòng 1: tên hiển thị, màu theo cosmetic đang dùng. Dòng 2: danh hiệu đang gắn (nếu có).
	Ẩn tên mặc định của Roblox để không hiện hai tên chồng nhau.
	Chỉ dựng Instance; CosmeticService quyết định nội dung.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local TAG_NAME = "ES_NameTag"

local NameTag = {}

local function newLabel(
	parent: Instance,
	name: string,
	font: Enum.Font,
	position: UDim2,
	size: UDim2
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.Position = position
	label.Size = size
	label.Parent = parent
	return label
end

-- Dựng (lần đầu) hoặc cập nhật bảng tên của một nhân vật. Trả về false nếu nhân vật chưa có đầu
-- (avatar R15 được dựng dần ngay sau khi xuất hiện), để bên gọi chờ rồi thử lại.
function NameTag.Apply(
	character: Model,
	displayName: string,
	title: string,
	color: Color3,
	fame: number?
): boolean
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local gui = head:FindFirstChild(TAG_NAME)
	if not gui then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = TAG_NAME
		billboard.Size = UDim2.fromOffset(220, 70)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = Config.Cosmetics.NameTagMaxDistance
		billboard.Parent = head
		newLabel(
			billboard,
			"Name",
			Enum.Font.SourceSansBold,
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 0.42)
		)
		newLabel(
			billboard,
			"Title",
			Enum.Font.SourceSansSemibold,
			UDim2.fromScale(0, 0.43),
			UDim2.fromScale(1, 0.29)
		)
		newLabel(
			billboard,
			"Fame",
			Enum.Font.SourceSansSemibold,
			UDim2.fromScale(0, 0.73),
			UDim2.fromScale(1, 0.27)
		)
		gui = billboard
	end
	local nameLabel = (gui :: Instance):FindFirstChild("Name") :: TextLabel?
	local titleLabel = (gui :: Instance):FindFirstChild("Title") :: TextLabel?
	if nameLabel then
		nameLabel.Text = displayName
		nameLabel.TextColor3 = color
	end
	if titleLabel then
		titleLabel.Text = title
		titleLabel.TextColor3 = Config.Cosmetics.TitleColor
		titleLabel.Visible = title ~= ""
	end
	-- Dòng Nổi tiếng: chỉ hiện khi có (đồ thời trang, tài sản thuê), để người chơi khoe thành quả
	local fameLabel = (gui :: Instance):FindFirstChild("Fame") :: TextLabel?
	if fameLabel then
		local shown = fame ~= nil and fame > 0
		fameLabel.Visible = shown
		fameLabel.TextColor3 = Config.Cosmetics.FameColor
		fameLabel.Text = if shown
			then string.format(Config.Text.NameTagFame, Format.number(fame :: number))
			else ""
	end
	return true
end

return NameTag
