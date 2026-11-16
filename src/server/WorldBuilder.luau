--!strict
--[[
	WorldBuilder — dựng sẵn thị trấn của Equal Social bằng code để nhấn Play là chơi được ngay.

	Nếu Workspace ĐÃ có `World` (Folder/Model do bạn tự làm) thì WorldBuilder không làm gì cả.
	Các service gắn ProximityPrompt theo TAG, nên khi thay bằng map riêng chỉ cần:
	  * gắn tag  Config.Tags.Job / Station / Shop / Class  (CollectionService)
	  * đặt attribute  JobId / StationId / ShopId / ClassId  trùng với id trong Config
	  * Bãi luyện tập: các điểm xuất hiện gắn tag MonsterSpawn + attribute MonsterId; Bệnh xá gắn tag
	    Infirmary; bảng xếp hạng 3D gắn tag Leaderboard (LeaderboardService tự vẽ nội dung)
	  * model có ít nhất một BasePart (prompt gắn vào PrimaryPart hoặc part đầu tiên)

	Bố cục: quảng trường tròn ở giữa (điểm hồi sinh), bốn con đường vòng nối bốn dãy phố:
	  tây = nghề, đông = trạm nghỉ + Trụ sở AURA + Khu tài sản, bắc = cửa hàng + Đấu trường,
	  nam = bảng xếp hạng + trường học + Bãi luyện tập + Bệnh xá.
	Công trình xếp tự động theo Config.Jobs / Classes / Stations / Shops (sắp theo id), nên thêm một mục
	trong Config là tự có công trình mới trên map (hình dáng: server/World/Buildings).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Calendar = require(ReplicatedStorage.Shared.Calendar)
local Config = require(ReplicatedStorage.Shared.Config)
local Describe = require(script.Parent.Util.Describe)
local Buildings = require(script.Parent.World.Buildings)
local Environment = require(script.Parent.World.Environment)
local Kit = require(script.Parent.World.Kit)
local Landmarks = require(script.Parent.World.Landmarks)
local Props = require(script.Parent.World.Props)

local P = Kit.Palette
local World = Config.World

local LABEL_HEIGHT = 6.5 -- nhãn nổi cách điểm tương tác ngần này studs
local TREE_MIN_GAP = 9 -- khoảng cách tối thiểu giữa hai cây

type Entry = {
	Id: string,
	Name: string, -- tên trên nhãn nổi (nghề có điều kiện kèm "(cần ...)")
	Sign: string, -- chữ trên biển hiệu
	Hint: string,
	Color: Color3?,
	Size: Vector3?,
}

type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

local WorldBuilder = {}

-- Vùng đã có công trình / đường: cây rải ngẫu nhiên sẽ tránh các vùng này
local reserved: { Rect } = {}
local paveLayer = 0

local function sortedIds(dictionary: { [string]: any }): { string }
	local ids: { string } = {}
	for id in dictionary do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function reserve(minX: number, maxX: number, minZ: number, maxZ: number)
	table.insert(reserved, {
		MinX = math.min(minX, maxX),
		MaxX = math.max(minX, maxX),
		MinZ = math.min(minZ, maxZ),
		MaxZ = math.max(minZ, maxZ),
	})
end

local function isFree(x: number, z: number, margin: number): boolean
	for _, rect in reserved do
		if
			x > rect.MinX - margin
			and x < rect.MaxX + margin
			and z > rect.MinZ - margin
			and z < rect.MaxZ + margin
		then
			return false
		end
	end
	return true
end

-- Mảng lát đường hình chữ nhật (chỉ để nhìn: không va chạm). Mỗi mảng cao hơn mảng trước một chút
-- để các mảng chồng nhau không bị nhấp nháy.
local function pave(
	parent: Instance,
	name: string,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	color: Color3?,
	material: Enum.Material?
)
	paveLayer += 1
	local lift = 0.004 * paveLayer
	local center = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
	local width, depth = math.abs(maxX - minX), math.abs(maxZ - minZ)
	Kit.decor(
		Kit.block(
			parent,
			name .. "Edge",
			Vector3.new(width + 1.2, 0.2, depth + 1.2),
			CFrame.new(center + Vector3.new(0, -0.07 + lift, 0)),
			P.PathEdge,
			Enum.Material.Concrete
		)
	)
	Kit.decor(
		Kit.block(
			parent,
			name,
			Vector3.new(width, 0.2, depth),
			CFrame.new(center + Vector3.new(0, -0.03 + lift, 0)),
			color or P.Path,
			material or Enum.Material.Concrete
		)
	)
	reserve(minX, maxX, minZ, maxZ)
end

-- ───────────────────────────── Mặt đất và ranh giới ─────────────────────────────

local function buildGround(world: Instance)
	local folder = Kit.folder(world, "Ground")
	-- Template Studio có sẵn Baseplate (mặt trên ở y = 0): thảm cỏ đặt nhô lên một chút cho khỏi trùng mặt
	local top = if Workspace:FindFirstChild("Baseplate") then 0.03 else 0
	local size = World.SceneryGroundSize
	local ground = Kit.block(
		folder,
		"Ground",
		Vector3.new(size, 2, size),
		CFrame.new(0, top - 1, 0),
		P.Grass,
		Enum.Material.Grass
	)
	ground.CastShadow = false

	-- Tường vô hình quanh vùng chơi
	local half = World.GroundSize / 2
	local height = World.BoundaryHeight
	for _, side in { -1, 1 } do
		local wallX = Kit.zone(
			folder,
			"Boundary",
			Vector3.new(2, height, World.GroundSize + 4),
			CFrame.new(side * (half + 1), height / 2, 0)
		)
		wallX.CanCollide = true
		local wallZ = Kit.zone(
			folder,
			"Boundary",
			Vector3.new(World.GroundSize + 4, height, 2),
			CFrame.new(0, height / 2, side * (half + 1))
		)
		wallZ.CanCollide = true
	end

	-- Đồi thấp phía xa cho đường chân trời đỡ trống
	local random = Random.new(World.TreeSeed)
	for index = 1, 14 do
		local angle = index / 14 * math.pi * 2 + random:NextNumber(-0.15, 0.15)
		local distance = random:NextNumber(half + 190, half + 420)
		local diameter = random:NextNumber(220, 380)
		local hill = Kit.ball(
			folder,
			"Hill",
			diameter,
			CFrame.new(math.cos(angle) * distance, -diameter * 0.34, math.sin(angle) * distance),
			if index % 2 == 0 then P.GrassDark else P.Leaf,
			Enum.Material.Grass
		)
		Kit.decor(hill)
	end
end

-- ───────────────────────────── Đường sá ─────────────────────────────

-- Tim bốn con đường vòng (trước mặt bốn dãy phố)
local function streetCenters(): (number, number, number, number)
	local west = World.JobsOrigin.X + World.StreetOffset
	local east = World.StationsOrigin.X - World.StreetOffset
	local north = World.ShopsOrigin.Z + World.StreetOffset
	local south = World.SchoolOrigin.Z - World.StreetOffset
	return west, east, north, south
end

local function buildStreets(world: Instance)
	local folder = Kit.folder(world, "Streets")
	local half = World.StreetWidth / 2
	local radius = World.PlazaRadius
	local west, east, north, south = streetCenters()

	-- Bốn đường vòng
	pave(folder, "StreetWest", west - half, west + half, north - half, south + half)
	pave(folder, "StreetEast", east - half, east + half, north - half, south + half)
	pave(folder, "StreetNorth", west - half, east + half, north - half, north + half)
	pave(folder, "StreetSouth", west - half, east + half, south - half, south + half)

	-- Bốn lối từ quảng trường ra đường vòng
	local spoke = 4
	pave(folder, "SpokeWest", west + half, -radius + 2, -spoke, spoke)
	pave(folder, "SpokeEast", radius - 2, east - half, -spoke, spoke)
	pave(folder, "SpokeNorth", -spoke, spoke, north + half, -radius + 2)
	pave(folder, "SpokeSouth", -spoke, spoke, radius - 2, south - half)
	reserve(-radius - 3, radius + 3, -radius - 3, radius + 3)

	-- Sân bảng xếp hạng (bảng đứng giữa lối nam nên lát rộng để đi vòng hai bên)
	local board = World.LeaderboardOrigin
	local boardHalf = World.LeaderboardSize.X / 2 + 10
	pave(
		folder,
		"BoardSquare",
		board.X - boardHalf,
		board.X + boardHalf,
		board.Z - 15,
		south - half,
		P.Plaza,
		Enum.Material.Cobblestone
	)

	-- Lối bắc tới quầy Đấu trường (đi giữa hai cửa hàng)
	local kiosk = World.ArenaOrigin + World.ArenaKioskOffset
	pave(folder, "ArenaWalk", -spoke, spoke, kiosk.Z + 6, north - half)
	pave(
		folder,
		"ArenaForecourt",
		-16,
		16,
		World.ArenaOrigin.Z + World.ArenaFloorSize / 2 - 2,
		kiosk.Z + 8,
		P.Plaza,
		Enum.Material.Cobblestone
	)

	-- Lối nam tới cổng Bãi luyện tập (đi giữa các lớp học)
	local zone = World.MonsterZoneOrigin
	pave(folder, "TrainingWalk", -spoke, spoke, south + half, zone.Z - World.MonsterZoneSize / 2)

	-- Đường tới Bệnh xá: kéo dài đường nam sang tây rồi rẽ xuống
	local infirmary = World.InfirmaryOrigin
	pave(folder, "InfirmaryRoad", infirmary.X - spoke, west - half, south - spoke, south + spoke)
	pave(
		folder,
		"InfirmaryWalk",
		infirmary.X - spoke,
		infirmary.X + spoke,
		south + spoke,
		infirmary.Z - World.InfirmarySize.Z / 2 - 10
	)

	-- Sảnh trước Trụ sở AURA và lối sang Khu tài sản
	local aura = World.AuraOrigin
	pave(
		folder,
		"AuraForecourt",
		east + half,
		aura.X - World.AuraSize.Z / 2,
		aura.Z - World.AuraSize.X / 2 - 2,
		aura.Z + World.AuraSize.X / 2 + 2,
		P.Plaza,
		Enum.Material.Cobblestone
	)
	local showcase = World.ShowcaseOrigin
	pave(
		folder,
		"ShowcaseWalk",
		east + half,
		showcase.X - 26,
		showcase.Z - spoke,
		showcase.Z + spoke
	)

	-- Đèn đường dọc mép trong của đường vòng
	local inner = half + 1.6
	for _, z in { north + 12, -18, 18, south - 12 } do
		Props.lamp(folder, Vector3.new(west + inner, 0, z))
		Props.lamp(folder, Vector3.new(east - inner, 0, z))
	end
	for _, x in { -18, 18 } do
		Props.lamp(folder, Vector3.new(x, 0, north + inner))
		Props.lamp(folder, Vector3.new(x, 0, south - inner))
	end
end

-- ───────────────────────────── Dãy công trình theo Config ─────────────────────────────

-- Xếp một nhóm công trình thành hàng dọc theo `axis`, căn giữa quanh `origin`, mặt tiền quay về `facing`
local function placeGroup(
	world: Instance,
	groupName: string,
	entries: { Entry },
	origin: Vector3,
	axis: Vector3,
	facing: Vector3,
	tag: string,
	attribute: string
)
	local folder = Kit.folder(world, groupName)
	local count = #entries
	for index, entry in entries do
		local size = entry.Size or World.DefaultSize
		local position = origin + axis * ((index - (count + 1) / 2) * World.Spacing)
		local anchor = Buildings.Build(folder, {
			Id = entry.Id,
			Base = CFrame.lookAt(position, position + facing),
			Size = size,
			Color = entry.Color or World.DefaultColor,
			Title = entry.Sign,
		})
		anchor:SetAttribute(attribute, entry.Id)
		Kit.label(anchor, entry.Name, entry.Hint, LABEL_HEIGHT)
		-- Gắn tag SAU khi đã vào Workspace và đã có attribute
		CollectionService:AddTag(anchor, tag)

		-- Chừa chỗ cho công trình và khoảng sân trước mặt
		local halfWidth, halfDepth = size.X / 2 + 5, size.Z / 2 + 2
		local back = position - facing * halfDepth
		local front = position + facing * (halfDepth + 8)
		local side = axis * halfWidth
		reserve(
			math.min(back.X, front.X) - math.abs(side.X),
			math.max(back.X, front.X) + math.abs(side.X),
			math.min(back.Z, front.Z) - math.abs(side.Z),
			math.max(back.Z, front.Z) + math.abs(side.Z)
		)
	end
end

local function hint(holdDuration: number, actionText: string): string
	local format = if holdDuration > 0 then Config.Text.WorldHintHold else Config.Text.WorldHintTap
	return string.format(format, actionText)
end

local function buildDistricts(world: Instance): (number, number, number, number)
	local jobs: { Entry } = {}
	for _, id in sortedIds(Config.Jobs) do
		local def = Config.Jobs[id]
		table.insert(jobs, {
			Id = id,
			Name = Describe.JobTitle(def), -- nghề có điều kiện hiện kèm "(cần ...)"
			Sign = def.Name,
			Hint = hint(def.HoldDuration, def.ActionText),
			Color = def.Color,
			Size = def.Size,
		})
	end
	placeGroup(
		world,
		"Jobs",
		jobs,
		World.JobsOrigin,
		Vector3.zAxis,
		Vector3.xAxis,
		Config.Tags.Job,
		Config.Attributes.Job
	)

	local stations: { Entry } = {}
	for _, id in sortedIds(Config.Stations) do
		local def = Config.Stations[id]
		table.insert(stations, {
			Id = id,
			Name = def.Name,
			Sign = def.Name,
			Hint = hint(def.HoldDuration, def.ActionText),
			Color = def.Color,
			Size = def.Size,
		})
	end
	placeGroup(
		world,
		"Stations",
		stations,
		World.StationsOrigin,
		Vector3.zAxis,
		-Vector3.xAxis,
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
			Sign = def.Name,
			Hint = hint(0, def.ActionText),
			Color = def.Color,
			Size = def.Size,
		})
	end
	placeGroup(
		world,
		"Shops",
		shops,
		World.ShopsOrigin,
		Vector3.xAxis,
		Vector3.zAxis,
		Config.Tags.Shop,
		Config.Attributes.Shop
	)

	-- Trường học: nhãn ghi kèm ngày mở cửa
	local classes: { Entry } = {}
	for _, id in sortedIds(Config.Classes) do
		local def = Config.Classes[id]
		table.insert(classes, {
			Id = id,
			Name = def.Name,
			Sign = def.Name,
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
		World.SchoolOrigin,
		Vector3.xAxis,
		-Vector3.zAxis,
		Config.Tags.Class,
		Config.Attributes.Class
	)
	return #jobs, #classes, #stations, #shops
end

-- ───────────────────────────── Cây cối ─────────────────────────────

local function scatterTrees(world: Instance)
	local folder = Kit.folder(world, "Nature")
	local random = Random.new(World.TreeSeed)
	local limit = World.GroundSize / 2 - 8
	local placed: { Vector3 } = {}

	local function farFromOthers(position: Vector3): boolean
		for _, other in placed do
			if (other - position).Magnitude < TREE_MIN_GAP then
				return false
			end
		end
		return true
	end

	local function plant(position: Vector3)
		local roll = random:NextNumber()
		local scale = random:NextNumber(0.85, 1.35)
		if roll < 0.55 then
			Props.tree(folder, position, scale, random:NextInteger(0, 2))
		elseif roll < 0.85 then
			Props.pine(folder, position, scale)
		elseif roll < 0.95 then
			Props.bush(folder, position, scale)
		else
			Props.rock(folder, position, scale, random:NextInteger(1, 1000))
		end
		table.insert(placed, position)
	end

	-- Trong vùng chơi: thử vị trí ngẫu nhiên, bỏ qua chỗ có công trình hoặc đường
	local attempts = 0
	while #placed < World.TreeCount and attempts < World.TreeCount * 30 do
		attempts += 1
		local position =
			Vector3.new(random:NextNumber(-limit, limit), 0, random:NextNumber(-limit, limit))
		if isFree(position.X, position.Z, 5) and farFromOthers(position) then
			plant(position)
		end
	end

	-- Ngoài tường vô hình: một vành rừng cho map có chiều sâu
	local half = World.GroundSize / 2
	for index = 1, 70 do
		local angle = index / 70 * math.pi * 2 + random:NextNumber(-0.04, 0.04)
		local distance = random:NextNumber(half * 1.45, half * 2.3)
		plant(Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
	end
end

-- Hồ, đài phun và vài chi tiết công viên ở những khoảng trống cố định
local function buildParks(world: Instance)
	local folder = Kit.folder(world, "Parks")
	local west, east, north, south = streetCenters()

	-- Hồ nước ở góc đông bắc (sau dãy trạm nghỉ)
	local pond = Vector3.new(east + 52, 0, north - 30)
	Props.pond(folder, pond, 16)
	reserve(pond.X - 20, pond.X + 20, pond.Z - 20, pond.Z + 20)
	Props.bench(folder, CFrame.lookAt(pond + Vector3.new(-21, 0, 6), pond))
	Props.bench(folder, CFrame.lookAt(pond + Vector3.new(6, 0, 22), pond))

	-- Đài phun nước ở hai vườn nhỏ giữa quảng trường và đường vòng (góc tây bắc và đông nam)
	for _, corner in
		{ Vector3.new(west + 14, 0, north + 14), Vector3.new(east - 13, 0, south - 20) }
	do
		Props.fountain(folder, corner)
		reserve(corner.X - 8, corner.X + 8, corner.Z - 8, corner.Z + 8)
	end
	-- Hai vườn còn lại: bồn hoa lớn
	for index, corner in
		{ Vector3.new(east - 14, 0, north + 14), Vector3.new(west + 13, 0, south - 20) }
	do
		Props.flowerBed(folder, CFrame.new(corner), 10, 6, 50 + index)
		-- Cây đứng về phía quảng trường để không lấn ra đường
		Props.tree(folder, corner - Vector3.new(0, 0, math.sign(corner.Z) * 8), 1.1, index)
		reserve(corner.X - 8, corner.X + 8, corner.Z - 12, corner.Z + 12)
	end
end

-- ───────────────────────────── Build ─────────────────────────────

function WorldBuilder.Build()
	if Workspace:FindFirstChild(World.FolderName) then
		print(
			`[WorldBuilder] Đã có '{World.FolderName}' trong Workspace -> dùng map có sẵn.`
		)
		return
	end

	table.clear(reserved)
	paveLayer = 0

	local world = Instance.new("Folder")
	world.Name = World.FolderName
	world.Parent = Workspace

	-- Bỏ qua điểm hồi sinh nếu map đã có SpawnLocation
	local hasSpawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true) ~= nil

	buildGround(world)
	buildStreets(world)
	Landmarks.Plaza(world, hasSpawn)
	Landmarks.WelcomeArch(world)

	local jobCount, classCount, stationCount, shopCount = buildDistricts(world)

	Landmarks.Leaderboard(world)
	Landmarks.AuraHq(world, -Vector3.xAxis)
	Landmarks.Arena(world)
	Landmarks.Infirmary(world)
	local spawnCount = Landmarks.MonsterZone(world)
	Landmarks.Showcase(world, -Vector3.xAxis)

	-- Chừa chỗ cho các công trình lớn trước khi rải cây
	local aura = World.AuraOrigin
	reserve(aura.X - 14, aura.X + 14, aura.Z - 16, aura.Z + 16)
	local arena = World.ArenaOrigin
	local arenaHalf = World.ArenaFloorSize / 2 + 24
	reserve(arena.X - arenaHalf, arena.X + arenaHalf, arena.Z - arenaHalf, arena.Z + arenaHalf + 16)
	local infirmary = World.InfirmaryOrigin
	reserve(infirmary.X - 14, infirmary.X + 14, infirmary.Z - 20, infirmary.Z + 12)
	local zone = World.MonsterZoneOrigin
	local zoneHalf = World.MonsterZoneSize / 2 + 3
	reserve(zone.X - zoneHalf, zone.X + zoneHalf, zone.Z - zoneHalf, zone.Z + zoneHalf)
	local showcase = World.ShowcaseOrigin
	local span = World.ShowcaseSpacing * 2
	reserve(showcase.X - 32, showcase.X + 30, showcase.Z - span, showcase.Z + span)

	buildParks(world)
	scatterTrees(world)
	Environment.Apply()

	print(
		`[WorldBuilder] Đã dựng map: {jobCount} nghề, {classCount} lớp học, {stationCount} trạm, {shopCount} cửa hàng, {spawnCount} điểm xuất hiện quái.`
	)
end

return WorldBuilder
