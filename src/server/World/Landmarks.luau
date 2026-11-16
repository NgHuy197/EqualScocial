--!strict
--[[
	Landmarks.luau — các công trình lớn, mỗi loại chỉ có một: quảng trường, cổng chào, bảng xếp hạng,
	Trụ sở AURA, Đấu trường, Bệnh xá, Bãi luyện tập và Khu tài sản AURA.

	Hàm nào tạo điểm tương tác thì tự gắn tag (Config.Tags) lên đúng part mà service cần:
	  * Leaderboard: tấm bảng (LeaderboardService vẽ lên mặt trước -Z).
	  * Aura: bàn điều khiển trước Trụ sở.
	  * Arena: thân quầy; ArenaPad: hai bục (attribute PadIndex).
	  * Infirmary: khối nhà chính (nhân vật hồi sinh ngay trước mặt -Z).
	  * MonsterSpawn: tấm mỏng vô hình tại mỗi điểm xuất hiện (attribute MonsterId).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)

local P = Kit.Palette

local Landmarks = {}

local function sortedIds(dictionary: { [string]: any }): { string }
	local ids: { string } = {}
	for id in dictionary do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function ground(position: Vector3): CFrame
	return CFrame.new(position.X, 0, position.Z)
end

-- ───────────────────────────── Quảng trường ─────────────────────────────

-- Sân lát tròn quanh điểm hồi sinh, có vòng viền, bồn hoa và ghế
function Landmarks.Plaza(world: Instance, hasSpawn: boolean)
	local folder = Kit.folder(world, "Plaza")
	local radius = Config.World.PlazaRadius
	local base = CFrame.new(0, 0, 0)

	Kit.cylinder(folder, "Rim", radius * 2 + 3, 0.2, Kit.at(base, 0, 0.02, 0), P.PathEdge).CastShadow =
		false
	local paving = Kit.cylinder(
		folder,
		"Paving",
		radius * 2,
		0.2,
		Kit.at(base, 0, 0.06, 0),
		P.Plaza,
		Enum.Material.Cobblestone
	)
	paving.CastShadow = false
	Kit.decor(
		Kit.cylinder(
			folder,
			"Ring",
			22,
			0.2,
			Kit.at(base, 0, 0.1, 0),
			Color3.fromRGB(196, 178, 150)
		)
	)
	Kit.decor(Kit.cylinder(folder, "RingInner", 19, 0.2, Kit.at(base, 0, 0.13, 0), P.Plaza))

	if not hasSpawn then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn"
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(12, 1, 12)
		spawn.Position = Vector3.new(0, 0.5, 0)
		spawn.Color = Color3.fromRGB(236, 232, 224)
		spawn.Material = Enum.Material.Marble
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.Parent = folder
		for _, child in spawn:GetChildren() do
			if child:IsA("Decal") then
				child:Destroy() -- bỏ hình mặc định của SpawnLocation
			end
		end
		local glow = Kit.block(
			folder,
			"SpawnGlow",
			Vector3.new(10, 0.1, 10),
			CFrame.new(0, 1.03, 0),
			P.AuraGlow,
			Enum.Material.Neon
		)
		Kit.decor(glow)
		glow.Transparency = 0.55
	end

	-- Bồn hoa và ghế ở bốn góc chéo, đèn ở bốn hướng xen kẽ
	for index = 0, 3 do
		local angle = math.pi / 4 + index * math.pi / 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local bedPosition = direction * (radius - 5)
		Props.flowerBed(folder, CFrame.lookAt(bedPosition, Vector3.zero), 6, 3, 31 + index)
		Props.bench(folder, CFrame.lookAt(direction * (radius - 9), Vector3.zero))
		Props.lamp(folder, direction * (radius + 0.5))
	end
end

-- Cổng chào: hai trụ và tấm biển lớn, chữ quay về phía điểm hồi sinh (-Z)
function Landmarks.WelcomeArch(world: Instance)
	local model = Kit.model(world, "WelcomeArch")
	local base =
		CFrame.lookAt(Config.World.WelcomeOrigin, Config.World.WelcomeOrigin - Vector3.zAxis)
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"Pillar",
			Vector3.new(1.6, 12, 1.6),
			Kit.at(base, side * 10, 6, 0),
			P.StoneDark,
			Enum.Material.Concrete
		)
		Kit.decor(
			Kit.block(
				model,
				"PillarGlow",
				Vector3.new(1.7, 0.4, 1.7),
				Kit.at(base, side * 10, 9, 0),
				P.AuraGlow,
				Enum.Material.Neon
			)
		)
	end
	local board = Kit.block(
		model,
		"Board",
		Vector3.new(21.6, 4.6, 0.8),
		Kit.at(base, 0, 12.6, 0),
		P.Night,
		Enum.Material.Metal
	)
	Kit.decor(
		Kit.block(
			model,
			"BoardTrim",
			Vector3.new(22.4, 0.4, 1),
			Kit.at(base, 0, 15, 0),
			P.AuraGlow,
			Enum.Material.Neon
		)
	)
	local text = string.format(Config.Text.WelcomeSign, Format.money(Config.Economy.StartingMoney))
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Kit.sign(board, face, text, { TextColor = P.White, Padding = 14, LightInfluence = 0 })
	end
end

-- Bảng xếp hạng 3D: tấm bảng mang tag, khung và mái che dựng quanh nó
function Landmarks.Leaderboard(world: Instance)
	local model = Kit.model(world, "LeaderboardStand")
	local size = Config.World.LeaderboardSize
	local origin = Config.World.LeaderboardOrigin
	local lift = 2 -- nâng bảng khỏi mặt đất
	local base = CFrame.lookAt(origin, origin - Vector3.zAxis)

	Kit.block(
		model,
		"Plinth",
		Vector3.new(size.X + 6, 1, 5),
		Kit.at(base, 0, 0.5, 0),
		P.StoneDark,
		Enum.Material.Concrete
	)
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"Post",
			Vector3.new(1.6, size.Y + lift + 2, 1.6),
			Kit.at(base, side * (size.X / 2 + 1.2), (size.Y + lift + 2) / 2, 0),
			P.MetalDark,
			Enum.Material.Metal
		)
	end
	Kit.block(
		model,
		"Header",
		Vector3.new(size.X + 5, 1.2, 2.4),
		Kit.at(base, 0, size.Y + lift + 1.4, 0),
		P.MetalDark,
		Enum.Material.Metal
	)
	Kit.decor(
		Kit.block(
			model,
			"HeaderGlow",
			Vector3.new(size.X + 2, 0.3, 2.5),
			Kit.at(base, 0, size.Y + lift + 0.7, 0),
			Color3.fromRGB(255, 205, 90),
			Enum.Material.Neon
		)
	)

	local board = Kit.block(
		world,
		"Leaderboard",
		size,
		CFrame.new(origin + Vector3.new(0, lift + size.Y / 2, 0)),
		P.Night
	)
	CollectionService:AddTag(board, Config.Tags.Leaderboard)
end

-- ───────────────────────────── Trụ sở AURA ─────────────────────────────

function Landmarks.AuraHq(world: Instance, facing: Vector3)
	local model = Kit.model(world, "AuraHq")
	local size = Config.World.AuraSize
	local origin = Config.World.AuraOrigin
	local base = CFrame.lookAt(origin, origin + facing)
	local w, h, d = size.X, size.Y, size.Z
	local front = Kit.face(base, w, d, "front")
	local dark = Color3.fromRGB(38, 40, 62)

	Kit.block(
		model,
		"Foundation",
		Vector3.new(w + 4, 0.8, d + 4),
		Kit.at(base, 0, 0.4, 0),
		P.StoneDark,
		Enum.Material.Concrete
	)
	Kit.block(
		model,
		"Hall",
		Vector3.new(w, h, d),
		Kit.at(base, 0, 0.8 + h / 2, 0),
		dark,
		Enum.Material.Metal
	)
	-- Tháp lõi cao phía sau và ba vành sáng
	local towerHeight = h * 2.6
	Kit.block(
		model,
		"Tower",
		Vector3.new(w * 0.5, towerHeight, d * 0.6),
		Kit.at(base, 0, 0.8 + towerHeight / 2, -d * 0.12),
		Color3.fromRGB(52, 54, 84),
		Enum.Material.Metal
	)
	for index = 1, 3 do
		Kit.decor(
			Kit.block(
				model,
				"Ring",
				Vector3.new(w * 0.5 + 0.6, 0.5, d * 0.6 + 0.6),
				Kit.at(base, 0, h + 2 + index * (towerHeight - h - 3) / 3, -d * 0.12),
				P.Aura,
				Enum.Material.Neon
			)
		)
	end
	local core = Kit.ball(
		model,
		"Core",
		5,
		Kit.at(base, 0, towerHeight + 5, -d * 0.12),
		P.AuraGlow,
		Enum.Material.Neon
	)
	Kit.decor(core)
	Kit.light(core, P.AuraGlow, 40, 1.4)
	Kit.decor(
		Kit.cylinder(
			model,
			"CoreRing",
			8.4,
			0.3,
			Kit.at(base, 0, towerHeight + 5, -d * 0.12)
				* CFrame.Angles(math.rad(24), 0, math.rad(12)),
			P.Aura,
			Enum.Material.Neon
		)
	)

	-- Mặt tiền: dải kính sáng và cửa
	for _, x in { -6, -2, 2, 6 } do
		local strip = Kit.block(
			model,
			"GlassStrip",
			Vector3.new(1.4, h - 3, 0.3),
			Kit.at(front, x, 0.8 + h / 2 + 0.6, 0.1),
			P.AuraGlow,
			Enum.Material.Neon
		)
		Kit.decor(strip)
		strip.Transparency = 0.35
	end
	Kit.decor(
		Kit.block(
			model,
			"Door",
			Vector3.new(4.4, 6.4, 0.3),
			Kit.at(front, 0, 4, 0.2),
			Color3.fromRGB(20, 22, 36),
			Enum.Material.Metal
		)
	)
	local sign = Kit.block(
		model,
		"SignBoard",
		Vector3.new(w - 4, 2, 0.5),
		Kit.at(front, 0, h + 0.4, 0.4),
		Color3.fromRGB(20, 22, 36)
	)
	Kit.decor(sign)
	Kit.sign(
		sign,
		Enum.NormalId.Front,
		Config.Text.AuraLabel,
		{ TextColor = P.AuraGlow, Padding = 8, LightInfluence = 0 }
	)

	-- Bàn điều khiển trước sảnh: điểm tương tác mở cửa sổ AURA
	Kit.block(
		model,
		"TerminalBase",
		Vector3.new(3.4, 0.6, 3.4),
		Kit.at(base, 0, 0.3, d / 2 + 5),
		P.MetalDark,
		Enum.Material.Metal
	)
	local terminal = Kit.block(
		model,
		"Terminal",
		Vector3.new(2.4, 3.4, 1.6),
		Kit.at(base, 0, 2.3, d / 2 + 5),
		dark,
		Enum.Material.Metal
	)
	local screen = Kit.block(
		model,
		"TerminalScreen",
		Vector3.new(2.8, 1.8, 0.2),
		Kit.at(base, 0, 4.6, d / 2 + 5.2) * CFrame.Angles(math.rad(20), 0, 0),
		P.AuraGlow,
		Enum.Material.Neon
	)
	Kit.decor(screen)
	Kit.light(screen, P.AuraGlow, 12, 0.8)
	for _, side in { -1, 1 } do
		Props.pine(model, Kit.at(base, side * (w / 2 + 3), 0, d / 2 + 1).Position, 0.8)
	end
	Kit.label(
		terminal,
		Config.Text.AuraLabel,
		string.format(Config.Text.WorldHintTap, Config.Text.AuraPrompt),
		5.4
	)
	model.PrimaryPart = terminal
	CollectionService:AddTag(terminal, Config.Tags.Aura)
end

-- ───────────────────────────── Đấu trường ─────────────────────────────

function Landmarks.Arena(world: Instance)
	local folder = Kit.folder(world, "Arena")
	local origin = Config.World.ArenaOrigin
	local base = ground(origin)
	local radius = Config.World.ArenaFloorSize / 2

	local floor = Kit.cylinder(
		folder,
		"ArenaFloor",
		radius * 2,
		0.4,
		Kit.at(base, 0, 0.2, 0),
		P.Sand,
		Enum.Material.Sand
	)
	floor.CastShadow = false
	Kit.decor(
		Kit.cylinder(
			folder,
			"CenterRing",
			16,
			0.1,
			Kit.at(base, 0, 0.42, 0),
			Color3.fromRGB(198, 172, 120)
		)
	)
	Kit.decor(Kit.cylinder(folder, "CenterDot", 13.6, 0.1, Kit.at(base, 0, 0.44, 0), P.Sand))

	-- Gờ đá thấp quanh sàn (nhảy qua được: ra khỏi vùng đấu vẫn là luật thua) và khán đài ba phía
	local segments = 24
	for index = 0, segments - 1 do
		local angle = index / segments * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = origin + direction * (radius + 1)
		local segment = CFrame.lookAt(position, position + direction)
		local chord = 2 * math.pi * (radius + 1) / segments + 0.4
		Kit.block(
			folder,
			"Curb",
			Vector3.new(chord, 1.2, 1.6),
			segment * CFrame.new(0, 0.6, 0),
			P.Stone,
			Enum.Material.Slate
		)
		-- Chừa lối vào phía quầy (+Z): không dựng khán đài ở cung đó
		if direction.Z < 0.55 then
			for tier = 1, 3 do
				local standPosition = origin + direction * (radius + 5 + tier * 3.4)
				local stand = CFrame.lookAt(standPosition, standPosition + direction)
				local standChord = 2 * math.pi * (radius + 5 + tier * 3.4) / segments + 0.5
				Kit.block(
					folder,
					"Stand",
					Vector3.new(standChord, tier * 2, 3.4),
					stand * CFrame.new(0, tier, 0),
					if tier % 2 == 1 then P.Concrete else P.Stone,
					Enum.Material.Concrete
				)
			end
			if index % 3 == 0 then
				local polePosition = origin + direction * (radius + 19)
				local pole = ground(polePosition)
				Kit.cylinder(folder, "FlagPole", 0.5, 16, Kit.at(pole, 0, 8, 0), P.MetalDark)
				Kit.decor(
					Kit.block(
						folder,
						"Flag",
						Vector3.new(0.2, 3, 4.4),
						CFrame.lookAt(polePosition, polePosition + direction)
							* CFrame.new(0, 14, 2.4),
						if index % 6 == 0
							then Color3.fromRGB(220, 90, 90)
							else Color3.fromRGB(80, 130, 220)
					)
				)
			end
		end
	end

	-- Hai bục xuất phát (mang tag; PvpService đọc vị trí)
	for index = 1, 2 do
		local side = if index == 1 then -1 else 1
		local color = if index == 1
			then Color3.fromRGB(220, 90, 90)
			else Color3.fromRGB(80, 130, 220)
		local pad = Kit.block(
			folder,
			`ArenaPad{index}`,
			Vector3.new(6, 1, 6),
			Kit.at(base, side * Config.World.ArenaPadOffset, 0.5, 0),
			color
		)
		Kit.decor(
			Kit.block(
				folder,
				"PadGlow",
				Vector3.new(4.6, 0.1, 4.6),
				Kit.at(base, side * Config.World.ArenaPadOffset, 1.03, 0),
				color:Lerp(Color3.new(1, 1, 1), 0.45),
				Enum.Material.Neon
			)
		)
		pad:SetAttribute(Config.Attributes.ArenaPad, index)
		CollectionService:AddTag(pad, Config.Tags.ArenaPad)
	end

	-- Quầy hàng chờ: thân quầy mang tag (giữ kích thước cũ vì PvpService đặt người chơi cạnh quầy)
	local kioskBase = ground(origin + Config.World.ArenaKioskOffset)
	local kioskSize = Vector3.new(10, 7, 6)
	local kiosk = Kit.block(
		folder,
		"ArenaKiosk",
		kioskSize,
		Kit.at(kioskBase, 0, kioskSize.Y / 2, 0),
		Color3.fromRGB(134, 80, 58),
		Enum.Material.WoodPlanks
	)
	Kit.block(
		folder,
		"KioskRoof",
		Vector3.new(12.4, 0.7, 8.4),
		Kit.at(kioskBase, 0, kioskSize.Y + 0.35, 0),
		Color3.fromRGB(200, 70, 60)
	)
	Kit.decor(
		Kit.block(
			folder,
			"KioskWindow",
			Vector3.new(6, 2.6, 0.3),
			Kit.at(kioskBase, 0, 4.4, -kioskSize.Z / 2 - 0.05),
			Color3.fromRGB(50, 34, 30)
		)
	)
	Kit.block(
		folder,
		"KioskShelf",
		Vector3.new(7, 0.4, 1.6),
		Kit.at(kioskBase, 0, 3, -kioskSize.Z / 2 - 0.8),
		P.WoodLight,
		Enum.Material.WoodPlanks
	)
	local sign = Kit.block(
		folder,
		"KioskSign",
		Vector3.new(9, 1.8, 0.4),
		Kit.at(kioskBase, 0, kioskSize.Y + 1.6, -kioskSize.Z / 2 - 0.4),
		P.Night
	)
	Kit.decor(sign)
	Kit.sign(
		sign,
		Enum.NormalId.Back,
		Config.Text.ArenaLabel,
		{ TextColor = Color3.fromRGB(255, 205, 90), Padding = 8 }
	)
	Kit.label(
		kiosk,
		Config.Text.ArenaLabel,
		string.format(Config.Text.WorldHintTap, Config.Text.ArenaPrompt),
		kioskSize.Y / 2 + 4.6
	)
	CollectionService:AddTag(kiosk, Config.Tags.Arena)
end

-- ───────────────────────────── Bệnh xá ─────────────────────────────

-- Mặt tiền quay về -Z: CombatService đặt nhân vật hồi sinh ngay trước mặt -Z của khối nhà chính
function Landmarks.Infirmary(world: Instance)
	local model = Kit.model(world, "InfirmaryBuilding")
	local size = Config.World.InfirmarySize
	local origin = Config.World.InfirmaryOrigin
	local base = CFrame.lookAt(origin, origin - Vector3.zAxis)
	local w, h, d = size.X, size.Y, size.Z
	local front = Kit.face(base, w, d, "front")
	local green = Color3.fromRGB(70, 180, 120)

	local body =
		Kit.block(world, "Infirmary", size, CFrame.new(origin + Vector3.new(0, h / 2, 0)), P.White)
	-- Tầng mái và mái dốc
	Kit.block(model, "Attic", Vector3.new(w, 3, d), Kit.at(base, 0, h + 1.5, 0), P.White)
	Kit.wedge(
		model,
		"Roof",
		Vector3.new(w + 1.8, 3, d / 2 + 0.9),
		Kit.at(base, 0, h + 4.5, d / 4 + 0.45),
		P.RoofTeal
	)
	Kit.wedge(
		model,
		"Roof",
		Vector3.new(w + 1.8, 3, d / 2 + 0.9),
		Kit.at(base, 0, h + 4.5, -d / 4 - 0.45) * CFrame.Angles(0, math.pi, 0),
		P.RoofTeal
	)
	Kit.decor(
		Kit.block(model, "Band", Vector3.new(w + 0.2, 0.8, 0.3), Kit.at(front, 0, h, 0.1), green)
	)
	-- Cửa kính và chữ thập xanh
	local doorGlass = Kit.block(
		model,
		"Door",
		Vector3.new(4, 5, 0.3),
		Kit.at(front, 0, 2.5, 0.1),
		P.Glass,
		Enum.Material.Glass
	)
	Kit.decor(doorGlass)
	doorGlass.Reflectance = 0.25
	Kit.decor(
		Kit.block(model, "CrossV", Vector3.new(1, 3, 0.3), Kit.at(front, 0, h + 1.6, 0.15), green)
	)
	Kit.decor(
		Kit.block(model, "CrossH", Vector3.new(3, 1, 0.3), Kit.at(front, 0, h + 1.6, 0.15), green)
	)
	for _, x in { -4.6, 4.6 } do
		Kit.decor(
			Kit.block(
				model,
				"Window",
				Vector3.new(2.6, 2.6, 0.3),
				Kit.at(front, x, 3.6, 0.1),
				P.Glass,
				Enum.Material.Glass
			)
		)
	end
	-- Sân hồi sức trước cửa
	Kit.decor(
		Kit.block(
			model,
			"Yard",
			Vector3.new(w + 6, 0.2, 10),
			Kit.at(base, 0, 0.05, d / 2 + 5),
			P.Plaza,
			Enum.Material.Cobblestone
		)
	)
	Props.bench(model, Kit.at(base, -w / 2 - 1, 0, d / 2 + 5) * CFrame.Angles(0, -math.pi / 2, 0))
	Props.lamp(model, Kit.at(base, w / 2 + 2, 0, d / 2 + 8).Position)
	Kit.label(body, Config.Text.InfirmaryLabel, Config.Text.InfirmaryHint, h / 2 + 9)
	CollectionService:AddTag(body, Config.Tags.Infirmary)
end

-- ───────────────────────────── Bãi luyện tập ─────────────────────────────

-- Trả về số điểm xuất hiện đã dựng
function Landmarks.MonsterZone(world: Instance): number
	local folder = Kit.folder(world, "MonsterZone")
	local origin = Config.World.MonsterZoneOrigin
	local base = ground(origin)
	local zoneSize = Config.World.MonsterZoneSize
	local half = zoneSize / 2

	local floor = Kit.block(
		folder,
		"Floor",
		Vector3.new(zoneSize, 0.4, zoneSize),
		Kit.at(base, 0, 0.2, 0),
		Color3.fromRGB(206, 188, 146),
		Enum.Material.Sand
	)
	floor.CastShadow = false

	-- Hàng rào quanh bãi, chừa cổng ở giữa cạnh -Z (phía thị trấn)
	local gate = 6
	local corners = {
		Vector3.new(-half, 0, -half),
		Vector3.new(half, 0, -half),
		Vector3.new(half, 0, half),
		Vector3.new(-half, 0, half),
	}
	Props.fence(folder, origin + corners[1], origin + Vector3.new(-gate, 0, -half))
	Props.fence(folder, origin + Vector3.new(gate, 0, -half), origin + corners[2])
	Props.fence(folder, origin + corners[2], origin + corners[3])
	Props.fence(folder, origin + corners[3], origin + corners[4])
	Props.fence(folder, origin + corners[4], origin + corners[1])

	-- Cổng gỗ có biển tên
	local gateBase =
		CFrame.lookAt(origin + Vector3.new(0, 0, -half), origin + Vector3.new(0, 0, -half - 1))
	for _, side in { -1, 1 } do
		Kit.block(
			folder,
			"GatePost",
			Vector3.new(1.2, 9, 1.2),
			Kit.at(gateBase, side * gate, 4.5, 0),
			P.WoodDark,
			Enum.Material.Wood
		)
	end
	local sign = Kit.block(
		folder,
		"Sign",
		Vector3.new(gate * 2 + 2, 2.6, 0.6),
		Kit.at(gateBase, 0, 9.6, 0),
		P.WoodDark,
		Enum.Material.WoodPlanks
	)
	Kit.sign(sign, Enum.NormalId.Front, Config.Text.MonsterZoneLabel, { TextColor = P.Cream })
	Kit.label(sign, Config.Text.MonsterZoneLabel, Config.Text.MonsterZoneHint, 3.6)

	-- Vài tảng đá và hình nộm tập luyện ở giữa bãi
	for index = 1, 6 do
		local angle = index * 1.9
		Props.rock(
			folder,
			origin + Vector3.new(math.cos(angle) * 12, 0.4, math.sin(angle) * 12),
			0.9,
			index * 5
		)
	end
	Kit.cylinder(
		folder,
		"DummyPost",
		0.8,
		5,
		Kit.at(base, 0, 2.9, 0),
		P.WoodDark,
		Enum.Material.Wood
	)
	Kit.block(
		folder,
		"DummyArms",
		Vector3.new(4.4, 0.7, 0.7),
		Kit.at(base, 0, 4, 0),
		P.WoodDark,
		Enum.Material.Wood
	)
	Kit.ball(folder, "DummyHead", 1.8, Kit.at(base, 0, 6, 0), P.Sand, Enum.Material.Fabric)

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
		local def = Config.Monsters[item.Id]
		-- Điểm xuất hiện là tấm mỏng vô hình trên sàn bãi (mặt trên sàn cao 0.4); đĩa màu chỉ để trang trí
		local point = Kit.zone(
			folder,
			`Spawn_{item.Id}_{index}`,
			Vector3.new(5, 0.2, 5),
			CFrame.new(origin + offset + Vector3.new(0, 0.5, 0))
		)
		local disc = Kit.cylinder(
			folder,
			"SpawnDisc",
			def.Size.X + 3,
			0.14,
			CFrame.new(origin + offset + Vector3.new(0, 0.47, 0)),
			def.Color:Lerp(Color3.fromRGB(206, 188, 146), 0.45)
		)
		Kit.decor(disc)
		point:SetAttribute(Config.Attributes.Monster, item.Id)
		CollectionService:AddTag(point, Config.Tags.MonsterSpawn)
	end
	return #plan
end

-- ───────────────────────────── Khu tài sản AURA ─────────────────────────────

local HOUSE_BUILDERS: { [string]: (parent: Instance, base: CFrame) -> () } = {
	boarding = Props.houseBoarding,
	apartment = Props.houseApartment,
	villa = Props.houseVilla,
}

local VEHICLE_COLORS = {
	Color3.fromRGB(226, 80, 70),
	Color3.fromRGB(70, 130, 210),
	Color3.fromRGB(250, 196, 60),
	Color3.fromRGB(90, 190, 140),
}

-- Trưng bày mọi tài sản trong Config.Assets (nhà một hàng phía sau, xe trên bục phía trước) kèm bảng
-- giá. Chỉ để ngắm: thuê và đấu giá vẫn làm ở Trụ sở AURA.
function Landmarks.Showcase(world: Instance, facing: Vector3)
	local folder = Kit.folder(world, "AssetShowcase")
	local origin = Config.World.ShowcaseOrigin
	local base = CFrame.lookAt(origin, origin + facing)

	local houses: { string } = {}
	local vehicles: { string } = {}
	for _, id in sortedIds(Config.Assets) do
		if Config.Assets[id].Kind == "house" then
			table.insert(houses, id)
		else
			table.insert(vehicles, id)
		end
	end
	local function byPrice(a: string, b: string): boolean
		return Config.Assets[a].Price < Config.Assets[b].Price
	end
	table.sort(houses, byPrice)
	table.sort(vehicles, byPrice)

	local function plaque(at: CFrame, id: string)
		local def = Config.Assets[id]
		Kit.block(
			folder,
			"PlaquePost",
			Vector3.new(0.5, 3, 0.5),
			Kit.at(at, 0, 1.5, 0),
			P.MetalDark
		)
		local board = Kit.block(
			folder,
			"Plaque",
			Vector3.new(10, 5, 0.4),
			Kit.at(at, 0, 5, 0) * CFrame.Angles(math.rad(12), 0, 0),
			P.Night
		)
		local line = string.format(
			Config.Text.ShowcasePlaque,
			def.Name,
			Format.money(def.Price),
			Format.money(def.FeePerCycle),
			def.Fame
		)
		if def.Stock then
			line ..= "\n" .. Config.Text.AssetRareButton
		end
		Kit.sign(
			board,
			Enum.NormalId.Front,
			line,
			{ TextColor = if def.Stock then Color3.fromRGB(255, 205, 90) else P.White, Padding = 8 }
		)
	end

	-- Sân lát và biển tên khu
	local span = math.max(#houses, #vehicles) * Config.World.ShowcaseSpacing
	Kit.decor(
		Kit.block(
			folder,
			"Court",
			Vector3.new(span + 8, 0.2, 30),
			Kit.at(base, 0, 0.05, 12),
			P.Plaza,
			Enum.Material.Cobblestone
		)
	)
	local banner = Kit.block(
		folder,
		"Banner",
		Vector3.new(26, 3, 0.6),
		Kit.at(base, 0, 9.5, 27),
		P.Night,
		Enum.Material.Metal
	)
	for _, side in { -1, 1 } do
		Kit.block(
			folder,
			"BannerPost",
			Vector3.new(1, 11, 1),
			Kit.at(base, side * 12.5, 5.5, 27),
			P.MetalDark,
			Enum.Material.Metal
		)
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Kit.sign(
			banner,
			face,
			Config.Text.ShowcaseLabel,
			{ TextColor = P.AuraGlow, Padding = 10, LightInfluence = 0 }
		)
	end

	for index, id in houses do
		local x = (index - (#houses + 1) / 2) * Config.World.ShowcaseSpacing
		local builder: (parent: Instance, base: CFrame) -> () = Props.houseBoarding
		local custom = HOUSE_BUILDERS[id]
		if custom then
			builder = custom
		end
		builder(folder, Kit.at(base, x, 0, -14))
		plaque(Kit.at(base, x - 9, 0, 0), id)
	end
	for index, id in vehicles do
		local x = (index - (#vehicles + 1) / 2) * Config.World.ShowcaseSpacing
		local spot = Kit.at(base, x, 0, 16)
		Kit.cylinder(
			folder,
			"Podium",
			15,
			0.6,
			Kit.at(spot, 0, 0.3, 0),
			P.StoneDark,
			Enum.Material.Concrete
		)
		Kit.decor(
			Kit.cylinder(
				folder,
				"PodiumGlow",
				15.4,
				0.15,
				Kit.at(spot, 0, 0.1, 0),
				P.AuraGlow,
				Enum.Material.Neon
			)
		)
		local color = VEHICLE_COLORS[((index - 1) % #VEHICLE_COLORS) + 1]
		local pose = Kit.at(spot, 0, 0.6, 0) * CFrame.Angles(0, math.rad(-35), 0)
		if id == "motorbike" then
			Props.motorbike(folder, pose, color)
		else
			Props.car(folder, pose, color, Config.Assets[id].Stock ~= nil)
		end
		plaque(Kit.at(spot, 0, 0, 9.4), id)
	end
end

return Landmarks
