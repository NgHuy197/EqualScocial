--!strict
--[[
	WorldBuilder — dựng map placeholder để nhấn Play là test được ngay.

	Nếu Workspace ĐÃ có `World` (Folder/Model do bạn tự làm) thì WorldBuilder không làm gì cả.
	Các service gắn ProximityPrompt theo TAG, nên khi thay bằng model thật chỉ cần:
	  * gắn tag  Config.Tags.Job / Station / Shop / Class  (CollectionService)
	  * đặt attribute  JobId / StationId / ShopId / ClassId  trùng với id trong Config
	  * Bãi luyện tập: các điểm xuất hiện gắn tag MonsterSpawn + attribute MonsterId; Bệnh xá gắn tag
	    Infirmary; bảng xếp hạng 3D gắn tag Leaderboard (LeaderboardService tự vẽ nội dung)
	  * model có ít nhất một BasePart (prompt gắn vào PrimaryPart hoặc part đầu tiên)

	Khối placeholder được xếp tự động theo Config.Jobs / Classes / Stations / Shops / Monsters (sắp theo id),
	nên thêm nghề, lớp học, trạm, cửa hàng hay loại quái mới trong Config là tự có khối mới trên map.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Calendar = require(ReplicatedStorage.Shared.Calendar)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Describe = require(script.Parent.Util.Describe)

-- Họ font Source Sans hiển thị tốt dấu tiếng Việt
local FONT_BOLD = Enum.Font.SourceSansBold
local FONT_REGULAR = Enum.Font.SourceSans

type Entry = {
	Id: string,
	Name: string,
	ActionText: string,
	HoldDuration: number,
	Hint: string?, -- thay cho dòng gợi ý mặc định (ví dụ lớp học kèm ngày mở)
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

-- Chữ tự co để vừa khung (tên dài như "Kỹ thuật viên (cần Khéo tay Lv.3)" không bị tràn)
local function fitText(label: TextLabel, maxTextSize: number)
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = label
end

-- Nhãn nổi phía trên khối: dòng tên + dòng gợi ý
local function addLabel(part: BasePart, title: string, subtitle: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Adornee = part
	gui.Size = UDim2.fromOffset(340, 64)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = Config.World.LabelMaxDistance
	gui.Parent = part

	local titleLabel = newLabel(gui, title, FONT_BOLD, 24)
	titleLabel.Size = UDim2.fromScale(1, 0.58)
	fitText(titleLabel, 24)

	local subtitleLabel = newLabel(gui, subtitle, FONT_REGULAR, 18)
	subtitleLabel.Position = UDim2.fromScale(0, 0.58)
	subtitleLabel.Size = UDim2.fromScale(1, 0.42)
	subtitleLabel.TextColor3 = Color3.fromRGB(215, 220, 230)
	fitText(subtitleLabel, 18)
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
		addLabel(part, entry.Name, entry.Hint or string.format(hintFormat, entry.ActionText))

		part.Parent = folder
		-- Gắn tag SAU khi đã vào Workspace và đã có attribute
		CollectionService:AddTag(part, tag)
	end
end

-- Trụ sở AURA: nhấn E để mở cửa sổ Tài sản / Đấu giá / Báo cáo (AuraService gắn prompt theo tag)
local function buildAuraHq(world: Folder)
	local size = Config.World.AuraSize
	local origin = Config.World.AuraOrigin
	local block = newBlock(
		"AuraHq",
		size,
		origin + Vector3.new(0, size.Y / 2, 0),
		Color3.fromRGB(86, 64, 150)
	)
	addLabel(
		block,
		Config.Text.AuraLabel,
		string.format(Config.Text.WorldHintTap, Config.Text.AuraPrompt)
	)
	block.Parent = world
	CollectionService:AddTag(block, Config.Tags.Aura)
end

-- Đấu trường: sàn đấu, hai bục xuất phát (tag ArenaPad + PadIndex) và quầy hàng chờ (tag Arena)
local function buildArena(world: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = world

	local origin = Config.World.ArenaOrigin
	local floorSize = Config.World.ArenaFloorSize
	local floor = newBlock(
		"ArenaFloor",
		Vector3.new(floorSize, 0.4, floorSize),
		origin + Vector3.new(0, 0.2, 0),
		Color3.fromRGB(205, 180, 140)
	)
	floor.Material = Enum.Material.Sand
	floor.CanCollide = false
	floor.Parent = folder

	for index = 1, 2 do
		local side = if index == 1 then -1 else 1
		local pad = newBlock(
			`ArenaPad{index}`,
			Vector3.new(6, 1, 6),
			origin + Vector3.new(side * Config.World.ArenaPadOffset, 0.5, 0),
			if index == 1 then Color3.fromRGB(220, 90, 90) else Color3.fromRGB(80, 130, 220)
		)
		pad:SetAttribute(Config.Attributes.ArenaPad, index)
		pad.Parent = folder
		CollectionService:AddTag(pad, Config.Tags.ArenaPad)
	end

	local kioskSize = Vector3.new(10, 7, 6)
	local kiosk = newBlock(
		"ArenaKiosk",
		kioskSize,
		origin + Config.World.ArenaKioskOffset + Vector3.new(0, kioskSize.Y / 2, 0),
		Color3.fromRGB(120, 70, 50)
	)
	addLabel(
		kiosk,
		Config.Text.ArenaLabel,
		string.format(Config.Text.WorldHintTap, Config.Text.ArenaPrompt)
	)
	kiosk.Parent = folder
	CollectionService:AddTag(kiosk, Config.Tags.Arena)
end

-- Bảng xếp hạng 3D ở quảng trường. LeaderboardService tự vẽ nội dung lên mặt trước (-Z) của part này.
local function buildLeaderboard(world: Folder)
	local size = Config.World.LeaderboardSize
	local origin = Config.World.LeaderboardOrigin
	local board = newBlock(
		"Leaderboard",
		size,
		origin + Vector3.new(0, size.Y / 2, 0),
		Color3.fromRGB(24, 28, 38)
	)
	board.Parent = world
	CollectionService:AddTag(board, Config.Tags.Leaderboard)
end

-- Bệnh xá: nơi hồi sinh khi bị quái đánh bại
local function buildInfirmary(world: Folder)
	local size = Config.World.InfirmarySize
	local origin = Config.World.InfirmaryOrigin
	local block = newBlock(
		"Infirmary",
		size,
		origin + Vector3.new(0, size.Y / 2, 0),
		Color3.fromRGB(235, 240, 245)
	)
	addLabel(block, Config.Text.InfirmaryLabel, Config.Text.InfirmaryHint)
	block.Parent = world
	CollectionService:AddTag(block, Config.Tags.Infirmary)
end

-- Bãi luyện tập: mảng sàn, biển báo và các điểm xuất hiện của quái xếp thành vòng tròn
local function buildMonsterZone(world: Folder): number
	local folder = Instance.new("Folder")
	folder.Name = "MonsterZone"
	folder.Parent = world

	local origin = Config.World.MonsterZoneOrigin
	local zoneSize = Config.World.MonsterZoneSize

	local floorPad = newBlock(
		"Floor",
		Vector3.new(zoneSize, 0.4, zoneSize),
		origin + Vector3.new(0, 0.2, 0),
		Color3.fromRGB(214, 190, 140)
	)
	floorPad.Material = Enum.Material.Sand
	floorPad.Parent = folder

	local sign = newBlock(
		"Sign",
		Vector3.new(10, 1, 1),
		origin + Vector3.new(0, 5, -zoneSize / 2),
		Color3.fromRGB(60, 64, 80)
	)
	addLabel(sign, Config.Text.MonsterZoneLabel, Config.Text.MonsterZoneHint)
	sign.Parent = folder

	-- Mỗi loại quái có SpawnPoints điểm; xen kẽ các loại quanh vòng tròn cho đều
	local plan: { { Key: number, Id: string } } = {}
	for _, id in sortedIds(Config.Monsters) do
		local def = Config.Monsters[id]
		for index = 1, def.SpawnPoints do
			table.insert(plan, { Key = (index - 0.5) / def.SpawnPoints, Id = id })
		end
	end
	table.sort(plan, function(a, b)
		if a.Key ~= b.Key then
			return a.Key < b.Key
		end
		return a.Id < b.Id
	end)

	for index, item in plan do
		local angle = (index - 1) / #plan * math.pi * 2
		local offset = Vector3.new(
			math.cos(angle) * Config.World.MonsterZoneRadius,
			0,
			math.sin(angle) * Config.World.MonsterZoneRadius
		)
		-- Điểm xuất hiện là một tấm mỏng nằm trên sàn bãi (mặt trên sàn cao 0.4)
		local point = newBlock(
			`Spawn_{item.Id}_{index}`,
			Vector3.new(5, 0.2, 5),
			origin + offset + Vector3.new(0, 0.5, 0),
			Config.Monsters[item.Id].Color
		)
		point.Transparency = 0.5
		point.CanCollide = false
		point:SetAttribute(Config.Attributes.Monster, item.Id)
		point.Parent = folder
		CollectionService:AddTag(point, Config.Tags.MonsterSpawn)
	end
	return #plan
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
			Name = Describe.JobTitle(def), -- nghề có điều kiện hiện kèm "(cần ...)"
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

	-- Trường học: các lớp xếp dọc trục X, nhãn ghi kèm ngày mở cửa
	local classes: { Entry } = {}
	for _, id in sortedIds(Config.Classes) do
		local def = Config.Classes[id]
		table.insert(classes, {
			Id = id,
			Name = def.Name,
			ActionText = def.ActionText,
			HoldDuration = def.HoldDuration,
			Hint = string.format(
				Config.Text.WorldHintClass,
				def.ActionText,
				Calendar.FormatDays(def.Days)
			),
			Color = def.Color,
			Size = def.Size,
		})
	end
	placeGroup(
		world,
		"School",
		classes,
		Config.World.SchoolOrigin,
		Vector3.new(1, 0, 0),
		Config.Tags.Class,
		Config.Attributes.Class
	)

	buildLeaderboard(world)
	buildAuraHq(world)
	buildArena(world)
	buildInfirmary(world)
	local spawnCount = buildMonsterZone(world)

	print(
		`[WorldBuilder] Đã dựng map placeholder: {#jobs} nghề, {#classes} lớp học, {#stations} trạm, {#shops} cửa hàng, {spawnCount} điểm xuất hiện quái.`
	)
end

return WorldBuilder
