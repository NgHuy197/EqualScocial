--!strict
--[[
	WorldBuilder — dựng map placeholder để nhấn Play là test được ngay.

	Nếu Workspace ĐÃ có `World` (Folder/Model do bạn tự làm) thì WorldBuilder không làm gì cả.
	Các service gắn ProximityPrompt theo TAG, nên khi thay bằng model thật chỉ cần:
	  * gắn tag  Config.Tags.Job / Station / Shop  (CollectionService)
	  * đặt attribute  JobId / StationId / ShopId  trùng với id trong Config
	  * model có ít nhất một BasePart (prompt gắn vào PrimaryPart hoặc part đầu tiên)

	Khối placeholder được xếp tự động theo Config.Jobs / Stations / Shops (sắp theo id), nên thêm
	nghề, trạm hoặc cửa hàng mới trong Config là tự có khối mới trên map.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

-- Họ font Source Sans hiển thị tốt dấu tiếng Việt
local FONT_BOLD = Enum.Font.SourceSansBold
local FONT_REGULAR = Enum.Font.SourceSans

type Entry = {
	Id: string,
	Name: string,
	ActionText: string,
	HoldDuration: number,
	Color: Color3?,
	Size: Vector3?,
}

local WorldBuilder = {}

local function sortedIds(dictionary: { [string]: any }): { string }
	local ids: { string } = {}
	for id in dictionary do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function newLabel(
	parent: Instance,
	text: string,
	font: Enum.Font,
	textSize: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.TextWrapped = true
	label.Parent = parent
	return label
end

-- Nhãn nổi phía trên khối: dòng tên + dòng gợi ý
local function addLabel(part: BasePart, title: string, subtitle: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Adornee = part
	gui.Size = UDim2.fromOffset(280, 64)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = Config.World.LabelMaxDistance
	gui.Parent = part

	local titleLabel = newLabel(gui, title, FONT_BOLD, 24)
	titleLabel.Size = UDim2.fromScale(1, 0.58)

	local subtitleLabel = newLabel(gui, subtitle, FONT_REGULAR, 18)
	subtitleLabel.Position = UDim2.fromScale(0, 0.58)
	subtitleLabel.Size = UDim2.fromScale(1, 0.42)
	subtitleLabel.TextColor3 = Color3.fromRGB(215, 220, 230)
end

local function newBlock(name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	return part
end

-- Xếp một nhóm khối thành hàng dọc theo `axis`, căn giữa quanh `origin`
local function placeGroup(
	world: Folder,
	groupName: string,
	entries: { Entry },
	origin: Vector3,
	axis: Vector3,
	tag: string,
	attribute: string
)
	local folder = Instance.new("Folder")
	folder.Name = groupName
	folder.Parent = world

	local count = #entries
	for index, entry in entries do
		local size = entry.Size or Config.World.DefaultSize
		local offset = axis * ((index - (count + 1) / 2) * Config.World.Spacing)
		local position = origin + offset + Vector3.new(0, size.Y / 2, 0)

		local part = newBlock(entry.Id, size, position, entry.Color or Config.World.DefaultColor)
		part:SetAttribute(attribute, entry.Id)

		local hintFormat = if entry.HoldDuration > 0
			then Config.Text.WorldHintHold
			else Config.Text.WorldHintTap
		addLabel(part, entry.Name, string.format(hintFormat, entry.ActionText))

		part.Parent = folder
		-- Gắn tag SAU khi đã vào Workspace và đã có attribute
		CollectionService:AddTag(part, tag)
	end
end

function WorldBuilder.Build()
	if Workspace:FindFirstChild(Config.World.FolderName) then
		print(
			`[WorldBuilder] Đã có '{Config.World.FolderName}' trong Workspace -> dùng map có sẵn.`
		)
		return
	end

	local world = Instance.new("Folder")
	world.Name = Config.World.FolderName
	world.Parent = Workspace

	-- Mặt đất (bỏ qua nếu template Studio đã có Baseplate, tránh hai mặt phẳng chồng nhau)
	if not Workspace:FindFirstChild("Baseplate") then
		local ground = newBlock(
			"Ground",
			Vector3.new(Config.World.GroundSize, 1, Config.World.GroundSize),
			Vector3.new(0, -0.5, 0),
			Color3.fromRGB(96, 140, 88)
		)
		ground.Material = Enum.Material.Grass
		ground.Parent = world
	end

	-- Điểm hồi sinh (bỏ qua nếu map đã có SpawnLocation)
	if not Workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn"
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(12, 1, 12)
		spawn.Position = Vector3.new(0, 0.5, 0)
		spawn.Color = Color3.fromRGB(210, 210, 215)
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.Parent = world
	end

	-- Biển chào mừng
	local sign = newBlock(
		"WelcomeSign",
		Vector3.new(14, 1, 1),
		Vector3.new(0, 6, 20),
		Color3.fromRGB(60, 64, 80)
	)
	local signGui = Instance.new("BillboardGui")
	signGui.Adornee = sign
	signGui.Size = UDim2.fromOffset(380, 90)
	signGui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	signGui.AlwaysOnTop = true
	signGui.MaxDistance = Config.World.LabelMaxDistance * 2
	signGui.Parent = sign
	local signLabel = newLabel(
		signGui,
		string.format(Config.Text.WelcomeSign, Format.money(Config.Economy.StartingMoney)),
		FONT_BOLD,
		22
	)
	signLabel.Size = UDim2.fromScale(1, 1)
	sign.Parent = world

	-- Nghề
	local jobs: { Entry } = {}
	for _, id in sortedIds(Config.Jobs) do
		local def = Config.Jobs[id]
		table.insert(jobs, {
			Id = id,
			Name = def.Name,
			ActionText = def.ActionText,
			HoldDuration = def.HoldDuration,
			Color = def.Color,
			Size = def.Size,
		})
	end
	placeGroup(
		world,
		"Jobs",
		jobs,
		Config.World.JobsOrigin,
		Vector3.new(0, 0, 1),
		Config.Tags.Job,
		Config.Attributes.Job
	)

	-- Trạm miễn phí
	local stations: { Entry } = {}
	for _, id in sortedIds(Config.Stations) do
		local def = Config.Stations[id]
		table.insert(stations, {
			Id = id,
			Name = def.Name,
			ActionText = def.ActionText,
			HoldDuration = def.HoldDuration,
			Color = def.Color,
			Size = def.Size,
		})
	end
	placeGroup(
		world,
		"Stations",
		stations,
		Config.World.StationsOrigin,
		Vector3.new(0, 0, 1),
		Config.Tags.Station,
		Config.Attributes.Station
	)

	-- Cửa hàng (nhấn E để mở, không cần giữ)
	local shops: { Entry } = {}
	for _, id in sortedIds(Config.Shops) do
		local def = Config.Shops[id]
		table.insert(shops, {
			Id = id,
			Name = def.Name,
			ActionText = def.ActionText,
			HoldDuration = 0,
			Color = def.Color,
			Size = def.Size,
		})
	end
	placeGroup(
		world,
		"Shops",
		shops,
		Config.World.ShopsOrigin,
		Vector3.new(1, 0, 0),
		Config.Tags.Shop,
		Config.Attributes.Shop
	)

	print(
		`[WorldBuilder] Đã dựng map placeholder: {#jobs} nghề, {#stations} trạm, {#shops} cửa hàng.`
	)
end

return WorldBuilder
