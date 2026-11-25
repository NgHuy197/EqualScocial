--!strict
--[[
	Props.luau — vật trang trí dùng lại nhiều lần: cây, bụi, đèn đường, ghế, hàng rào, thùng hàng,
	bàn ghế, hồ nước, xe cộ và nhà mẫu của Khu tài sản AURA.

	Chỉ dựng Instance, không có logic game. Mọi hàm nhận `parent` và vị trí / CFrame trên mặt đất.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.Kit)

local P = Kit.Palette

local Props = {}

local function ground(position: Vector3): CFrame
	return CFrame.new(position.X, 0, position.Z)
end

-- ───────────────────────────── Cây cối ─────────────────────────────

-- Cây tán tròn: thân trụ + ba cụm lá
function Props.tree(parent: Instance, position: Vector3, scale: number, variant: number)
	local model = Kit.model(parent, "Tree")
	local base = ground(position)
	local trunkHeight = 5 * scale
	Kit.cylinder(
		model,
		"Trunk",
		1.3 * scale,
		trunkHeight,
		Kit.at(base, 0, trunkHeight / 2, 0),
		P.Trunk,
		Enum.Material.Wood
	)
	local colors = { P.Leaf, P.LeafLight, P.LeafDark }
	local main = colors[(variant % 3) + 1]
	local accent = colors[((variant + 1) % 3) + 1]
	local crown = Kit.at(base, 0, trunkHeight + 2 * scale, 0)
	Kit.decor(Kit.ball(model, "Leaves", 7 * scale, crown, main)).CastShadow = true
	Kit.decor(
		Kit.ball(
			model,
			"Leaves",
			5 * scale,
			crown * CFrame.new(2.2 * scale, -0.8 * scale, 1 * scale),
			accent
		)
	)
	Kit.decor(
		Kit.ball(
			model,
			"Leaves",
			4.6 * scale,
			crown * CFrame.new(-2 * scale, 0.4 * scale, -1.2 * scale),
			accent
		)
	)
end

-- Cây thông: thân trụ + ba tầng lá thu nhỏ dần
function Props.pine(parent: Instance, position: Vector3, scale: number)
	local model = Kit.model(parent, "Pine")
	local base = ground(position)
	Kit.cylinder(
		model,
		"Trunk",
		1.1 * scale,
		3 * scale,
		Kit.at(base, 0, 1.5 * scale, 0),
		P.Trunk,
		Enum.Material.Wood
	)
	local tiers = { { 7, 3, 3.5 }, { 5.2, 3, 6 }, { 3.2, 3, 8.5 } }
	for index, tier in tiers do
		local part = Kit.cylinder(
			model,
			"Tier",
			tier[1] * scale,
			tier[2] * scale,
			Kit.at(base, 0, tier[3] * scale, 0),
			if index % 2 == 1 then P.LeafDark else P.Leaf
		)
		Kit.decor(part).CastShadow = true
	end
	Kit.decor(Kit.ball(model, "Top", 2 * scale, Kit.at(base, 0, 10.4 * scale, 0), P.LeafDark))
end

function Props.bush(parent: Instance, position: Vector3, scale: number)
	local base = ground(position)
	Kit.decor(Kit.ball(parent, "Bush", 3.4 * scale, Kit.at(base, 0, 1.1 * scale, 0), P.LeafDark))
	Kit.decor(
		Kit.ball(parent, "Bush", 2.6 * scale, Kit.at(base, 1.5 * scale, 0.9 * scale, 0.6), P.Leaf)
	)
end

-- Bồn hoa: viền đá, đất và vài bông hoa màu
function Props.flowerBed(parent: Instance, base: CFrame, width: number, depth: number, seed: number)
	local model = Kit.model(parent, "FlowerBed")
	Kit.block(model, "Rim", Vector3.new(width, 0.8, depth), Kit.at(base, 0, 0.4, 0), P.Stone)
	Kit.decor(
		Kit.block(
			model,
			"Soil",
			Vector3.new(width - 0.8, 0.3, depth - 0.8),
			Kit.at(base, 0, 0.8, 0),
			Color3.fromRGB(96, 70, 52),
			Enum.Material.Ground
		)
	)
	local random = Random.new(seed)
	local flowerColors = {
		Color3.fromRGB(255, 120, 150),
		Color3.fromRGB(255, 210, 90),
		Color3.fromRGB(240, 240, 250),
		Color3.fromRGB(190, 130, 255),
	}
	local count = math.max(3, math.floor(width * depth / 5))
	for _ = 1, count do
		local x = random:NextNumber(-width / 2 + 0.9, width / 2 - 0.9)
		local z = random:NextNumber(-depth / 2 + 0.9, depth / 2 - 0.9)
		Kit.decor(
			Kit.ball(model, "Leaf", 1.1, Kit.at(base, x, 1.1, z), P.Leaf, Enum.Material.Grass)
		)
		Kit.decor(
			Kit.ball(
				model,
				"Flower",
				0.7,
				Kit.at(base, x, 1.75, z),
				flowerColors[random:NextInteger(1, #flowerColors)]
			)
		)
	end
end

function Props.rock(parent: Instance, position: Vector3, scale: number, seed: number)
	local random = Random.new(seed)
	local size = Vector3.new(
		random:NextNumber(2, 3.4) * scale,
		random:NextNumber(1.4, 2.4) * scale,
		random:NextNumber(2, 3.2) * scale
	)
	local cf = CFrame.new(position.X, size.Y * 0.35, position.Z)
		* CFrame.Angles(
			random:NextNumber(-0.25, 0.25),
			random:NextNumber(0, math.pi),
			random:NextNumber(-0.25, 0.25)
		)
	Kit.block(parent, "Rock", size, cf, P.Stone, Enum.Material.Slate)
end

-- ───────────────────────────── Đô thị ─────────────────────────────

-- Đèn đường: bóng đèn mang tag Lamp, client bật sáng khi trời tối
function Props.lamp(parent: Instance, position: Vector3)
	local model = Kit.model(parent, "StreetLamp")
	local base = ground(position)
	Kit.cylinder(model, "Base", 1.4, 0.6, Kit.at(base, 0, 0.3, 0), P.MetalDark, Enum.Material.Metal)
	Kit.cylinder(model, "Pole", 0.45, 10, Kit.at(base, 0, 5.3, 0), P.MetalDark, Enum.Material.Metal)
	Kit.decor(
		Kit.block(
			model,
			"Cap",
			Vector3.new(2, 0.3, 2),
			Kit.at(base, 0, 11.6, 0),
			P.MetalDark,
			Enum.Material.Metal
		)
	)
	local bulb =
		Kit.block(model, "Bulb", Vector3.new(1.3, 1.2, 1.3), Kit.at(base, 0, 10.8, 0), P.Lamp)
	Kit.decor(bulb)
	bulb.Material = Enum.Material.SmoothPlastic
	local light = Kit.light(bulb, P.Lamp, 32, 0.9)
	light.Enabled = false
	CollectionService:AddTag(bulb, Config.Tags.Lamp)
end

-- Ghế băng (chỉ trang trí; trạm Ghế công viên dựng riêng trong Buildings)
function Props.bench(parent: Instance, base: CFrame): BasePart
	local model = Kit.model(parent, "Bench")
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"Leg",
			Vector3.new(0.4, 1.6, 2),
			Kit.at(base, side * 2.6, 0.8, 0),
			P.MetalDark,
			Enum.Material.Metal
		)
	end
	local seat = Kit.block(
		model,
		"Seat",
		Vector3.new(6.4, 0.4, 2.2),
		Kit.at(base, 0, 1.8, 0),
		P.Wood,
		Enum.Material.WoodPlanks
	)
	Kit.block(
		model,
		"Back",
		Vector3.new(6.4, 1.8, 0.4),
		Kit.at(base, 0, 3, -1.1) * CFrame.Angles(math.rad(8), 0, 0),
		P.Wood,
		Enum.Material.WoodPlanks
	)
	return seat
end

function Props.crate(parent: Instance, base: CFrame, size: number): Part
	local crate = Kit.block(
		parent,
		"Crate",
		Vector3.new(size, size, size),
		Kit.at(base, 0, size / 2, 0),
		P.WoodLight,
		Enum.Material.WoodPlanks
	)
	for _, side in { -1, 1 } do
		Kit.decor(
			Kit.block(
				parent,
				"CrateBand",
				Vector3.new(size + 0.1, 0.4, size + 0.1),
				Kit.at(base, 0, size / 2 + side * (size / 2 - 0.3), 0),
				P.WoodDark,
				Enum.Material.Wood
			)
		)
	end
	return crate
end

-- Bàn tròn có dù và hai ghế đẩu
function Props.cafeTable(parent: Instance, base: CFrame, umbrellaColor: Color3)
	local model = Kit.model(parent, "CafeTable")
	Kit.cylinder(model, "Leg", 0.4, 2.6, Kit.at(base, 0, 1.3, 0), P.MetalDark, Enum.Material.Metal)
	Kit.cylinder(model, "Top", 4, 0.3, Kit.at(base, 0, 2.7, 0), P.White)
	Kit.decor(
		Kit.cylinder(
			model,
			"Pole",
			0.25,
			6,
			Kit.at(base, 0, 5.8, 0),
			P.MetalDark,
			Enum.Material.Metal
		)
	)
	Kit.decor(Kit.cylinder(model, "Umbrella", 7, 0.5, Kit.at(base, 0, 8.6, 0), umbrellaColor))
	Kit.decor(Kit.cylinder(model, "UmbrellaTop", 3.4, 0.5, Kit.at(base, 0, 9.1, 0), P.White))
	for _, side in { -1, 1 } do
		Kit.cylinder(model, "Stool", 1.6, 1.6, Kit.at(base, side * 3, 0.8, 0), P.Wood)
	end
end

-- Hàng rào gỗ từ a tới b (toạ độ mặt đất)
function Props.fence(parent: Instance, a: Vector3, b: Vector3, color: Color3?)
	local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = delta.Magnitude
	if length < 0.5 then
		return
	end
	local tone = color or P.WoodLight
	local middle = Vector3.new((a.X + b.X) / 2, 0, (a.Z + b.Z) / 2)
	local base = CFrame.lookAt(middle, middle + delta.Unit)
	for _, height in { 1.2, 2.4 } do
		Kit.block(
			parent,
			"Rail",
			Vector3.new(0.3, 0.4, length),
			base * CFrame.new(0, height, 0),
			tone,
			Enum.Material.Wood
		)
	end
	local posts = math.max(1, math.floor(length / 6 + 0.5))
	for index = 0, posts do
		local offset = -length / 2 + length * index / posts
		Kit.block(
			parent,
			"Post",
			Vector3.new(0.6, 3.2, 0.6),
			base * CFrame.new(0, 1.6, offset),
			tone,
			Enum.Material.Wood
		)
	end
end

-- Hồ nước tròn có bờ đá
function Props.pond(parent: Instance, position: Vector3, radius: number)
	local model = Kit.model(parent, "Pond")
	local base = ground(position)
	Kit.decor(Kit.cylinder(model, "Shore", radius * 2 + 3, 0.3, Kit.at(base, 0, 0.05, 0), P.Sand))
	local water = Kit.cylinder(model, "Water", radius * 2, 0.3, Kit.at(base, 0, 0.12, 0), P.Water)
	Kit.decor(water)
	water.Material = Enum.Material.Glass
	water.Reflectance = 0.15
	water.Transparency = 0.15
	for index = 1, 9 do
		local angle = index / 9 * math.pi * 2
		Props.rock(
			model,
			position
				+ Vector3.new(math.cos(angle) * (radius + 0.8), 0, math.sin(angle) * (radius + 0.8)),
			0.55,
			index * 17
		)
	end
	for index = 1, 4 do
		local angle = index * 1.7
		Kit.decor(
			Kit.cylinder(
				model,
				"LilyPad",
				1.6,
				0.1,
				Kit.at(base, math.cos(angle) * radius * 0.5, 0.32, math.sin(angle) * radius * 0.5),
				P.LeafLight
			)
		)
	end
end

-- Đài phun nước nhỏ
function Props.fountain(parent: Instance, position: Vector3)
	local model = Kit.model(parent, "Fountain")
	local base = ground(position)
	Kit.cylinder(model, "Basin", 12, 1.4, Kit.at(base, 0, 0.7, 0), P.Stone, Enum.Material.Concrete)
	local water = Kit.cylinder(model, "Water", 10.6, 0.2, Kit.at(base, 0, 1.35, 0), P.Water)
	Kit.decor(water)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.2
	Kit.cylinder(model, "Column", 1.6, 4, Kit.at(base, 0, 2.6, 0), P.Stone, Enum.Material.Concrete)
	Kit.cylinder(model, "Bowl", 5, 0.6, Kit.at(base, 0, 4.8, 0), P.Stone, Enum.Material.Concrete)
	local core = Kit.ball(model, "Core", 1.8, Kit.at(base, 0, 6, 0), P.AuraGlow, Enum.Material.Neon)
	Kit.decor(core)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	emitter.Size = NumberSequence.new(0.35, 0.1)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(0.9, 1.3)
	emitter.Rate = 30
	emitter.Speed = NumberRange.new(7, 9)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, -26, 0)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.LightEmission = 0.4
	emitter.Parent = core
end

-- ───────────────────────────── Xe cộ (Khu tài sản AURA) ─────────────────────────────

local function wheel(
	model: Instance,
	base: CFrame,
	right: number,
	forward: number,
	diameter: number
)
	local cf = Kit.at(base, right, diameter / 2, forward) * CFrame.Angles(0, 0, math.pi / 2)
	Kit.cylinder(model, "Wheel", diameter, 0.9, cf, Color3.fromRGB(34, 36, 42))
	Kit.decor(Kit.cylinder(model, "Hub", diameter * 0.5, 1, cf, P.Concrete, Enum.Material.Metal))
end

function Props.motorbike(parent: Instance, base: CFrame, color: Color3)
	local model = Kit.model(parent, "Motorbike")
	wheel(model, base, 0, 2.4, 2.2)
	wheel(model, base, 0, -2.4, 2.2)
	Kit.block(model, "Body", Vector3.new(1.1, 1.2, 4.2), Kit.at(base, 0, 1.9, 0), color)
	Kit.block(
		model,
		"Seat",
		Vector3.new(1.2, 0.5, 2.4),
		Kit.at(base, 0, 2.7, -0.8),
		Color3.fromRGB(40, 40, 46)
	)
	Kit.block(
		model,
		"Fork",
		Vector3.new(0.4, 2.6, 0.4),
		Kit.at(base, 0, 2.6, 2.2) * CFrame.Angles(math.rad(18), 0, 0),
		P.Metal,
		Enum.Material.Metal
	)
	Kit.block(
		model,
		"Handle",
		Vector3.new(2.6, 0.3, 0.3),
		Kit.at(base, 0, 3.9, 1.8),
		P.MetalDark,
		Enum.Material.Metal
	)
	Kit.decor(
		Kit.ball(model, "Headlight", 0.8, Kit.at(base, 0, 3.2, 2.7), P.Lamp, Enum.Material.Neon)
	)
end

-- Ô tô; `sporty` = thân thấp, dài, có cánh gió
function Props.car(parent: Instance, base: CFrame, color: Color3, sporty: boolean)
	local model = Kit.model(parent, if sporty then "SportsCar" else "Car")
	local width = 6
	local length = if sporty then 13 else 11.5
	local bodyHeight = if sporty then 1.5 else 2
	for _, side in { -1, 1 } do
		wheel(model, base, side * (width / 2 - 0.2), length / 2 - 2.4, 2.2)
		wheel(model, base, side * (width / 2 - 0.2), -length / 2 + 2.4, 2.2)
	end
	Kit.block(
		model,
		"Body",
		Vector3.new(width, bodyHeight, length),
		Kit.at(base, 0, 1 + bodyHeight / 2, 0),
		color
	)
	local cabinLength = if sporty then 5 else 6
	local cabinHeight = if sporty then 1.4 else 1.9
	local cabinForward = if sporty then -0.8 else -0.4
	local cabin = Kit.block(
		model,
		"Cabin",
		Vector3.new(width - 0.8, cabinHeight, cabinLength),
		Kit.at(base, 0, 1 + bodyHeight + cabinHeight / 2, cabinForward),
		P.Glass,
		Enum.Material.Glass
	)
	cabin.Transparency = 0.25
	Kit.decor(
		Kit.block(
			model,
			"Roof",
			Vector3.new(width - 0.6, 0.3, cabinLength - 1),
			Kit.at(base, 0, 1 + bodyHeight + cabinHeight + 0.15, cabinForward),
			color
		)
	)
	for _, side in { -1, 1 } do
		Kit.decor(
			Kit.block(
				model,
				"Headlight",
				Vector3.new(1.2, 0.5, 0.2),
				Kit.at(base, side * 1.9, 1 + bodyHeight * 0.6, length / 2 + 0.05),
				P.Lamp,
				Enum.Material.Neon
			)
		)
		Kit.decor(
			Kit.block(
				model,
				"TailLight",
				Vector3.new(1.2, 0.4, 0.2),
				Kit.at(base, side * 1.9, 1 + bodyHeight * 0.6, -length / 2 - 0.05),
				Color3.fromRGB(235, 70, 70),
				Enum.Material.Neon
			)
		)
	end
	if sporty then
		for _, side in { -1, 1 } do
			Kit.decor(
				Kit.block(
					model,
					"SpoilerPost",
					Vector3.new(0.3, 1, 0.3),
					Kit.at(base, side * 2, 1 + bodyHeight + 0.5, -length / 2 + 0.8),
					P.MetalDark
				)
			)
		end
		Kit.decor(
			Kit.block(
				model,
				"Spoiler",
				Vector3.new(width, 0.25, 1.4),
				Kit.at(base, 0, 1 + bodyHeight + 1.1, -length / 2 + 0.8),
				P.MetalDark
			)
		)
		Kit.decor(
			Kit.block(
				model,
				"Stripe",
				Vector3.new(1.2, 0.05, length - 0.4),
				Kit.at(base, 0, 1 + bodyHeight + 0.03, 0),
				P.White
			)
		)
	end
end

-- ───────────────────────────── Nhà mẫu (Khu tài sản AURA) ─────────────────────────────

local function gable(
	model: Instance,
	base: CFrame,
	width: number,
	depth: number,
	y: number,
	rise: number,
	color: Color3
)
	Kit.wedge(
		model,
		"Roof",
		Vector3.new(width + 1.6, rise, depth / 2 + 0.8),
		Kit.at(base, 0, y + rise / 2, depth / 4 + 0.4),
		color
	)
	Kit.wedge(
		model,
		"Roof",
		Vector3.new(width + 1.6, rise, depth / 2 + 0.8),
		Kit.at(base, 0, y + rise / 2, -depth / 4 - 0.4) * CFrame.Angles(0, math.pi, 0),
		color
	)
end

local function frontWindow(
	model: Instance,
	base: CFrame,
	depth: number,
	x: number,
	y: number,
	w: number,
	h: number
)
	Kit.decor(
		Kit.block(
			model,
			"WindowFrame",
			Vector3.new(w + 0.5, h + 0.5, 0.3),
			Kit.at(base, x, y, depth / 2 + 0.05),
			P.White
		)
	)
	local glass = Kit.block(
		model,
		"Window",
		Vector3.new(w, h, 0.3),
		Kit.at(base, x, y, depth / 2 + 0.12),
		P.Glass,
		Enum.Material.Glass
	)
	Kit.decor(glass)
	glass.Reflectance = 0.2
end

-- Phòng trọ: nhà cấp bốn nhỏ
function Props.houseBoarding(parent: Instance, base: CFrame)
	local model = Kit.model(parent, "BoardingHouse")
	Kit.block(model, "Base", Vector3.new(15, 0.6, 12), Kit.at(base, 0, 0.3, 0), P.Concrete)
	Kit.block(model, "Walls", Vector3.new(14, 8, 11), Kit.at(base, 0, 4.6, 0), P.Cream)
	gable(model, base, 14, 11, 8.6, 3.4, P.RoofBrown)
	Kit.decor(
		Kit.block(
			model,
			"Door",
			Vector3.new(2.6, 5.4, 0.3),
			Kit.at(base, -3, 3.3, 5.55),
			P.WoodDark
		)
	)
	frontWindow(model, base, 11, 2.8, 5, 3.2, 2.8)
end

-- Căn hộ: khối ba tầng mái bằng
function Props.houseApartment(parent: Instance, base: CFrame)
	local model = Kit.model(parent, "Apartment")
	Kit.block(model, "Base", Vector3.new(19, 0.6, 15), Kit.at(base, 0, 0.3, 0), P.Concrete)
	Kit.block(
		model,
		"Walls",
		Vector3.new(18, 24, 14),
		Kit.at(base, 0, 12.6, 0),
		Color3.fromRGB(226, 214, 206)
	)
	Kit.block(model, "Roof", Vector3.new(19, 0.8, 15), Kit.at(base, 0, 25, 0), P.StoneDark)
	for floor = 0, 2 do
		local y = 5 + floor * 7.4
		for _, x in { -5.5, 0, 5.5 } do
			if not (floor == 0 and x == 0) then
				frontWindow(model, base, 14, x, y, 3, 3.4)
			end
		end
		if floor > 0 then
			Kit.block(
				model,
				"Balcony",
				Vector3.new(16, 0.4, 1.6),
				Kit.at(base, 0, y - 2.4, 7.8),
				P.Concrete
			)
		end
	end
	Kit.decor(
		Kit.block(model, "Door", Vector3.new(3, 5.6, 0.3), Kit.at(base, 0, 3.4, 7.05), P.MetalDark)
	)
end

-- Biệt thự: hai tầng, mái dốc, có hiên và hồ bơi nhỏ
function Props.houseVilla(parent: Instance, base: CFrame)
	local model = Kit.model(parent, "Villa")
	Kit.block(model, "Base", Vector3.new(29, 0.8, 21), Kit.at(base, 0, 0.4, 0), P.Concrete)
	Kit.block(model, "Walls", Vector3.new(26, 11, 16), Kit.at(base, 0, 6.3, -1.5), P.White)
	Kit.block(
		model,
		"Upper",
		Vector3.new(16, 8, 14),
		Kit.at(base, -5, 15.8, -1.5),
		Color3.fromRGB(238, 232, 220)
	)
	gable(model, Kit.at(base, -5, 0, -1.5), 16, 14, 19.8, 4, P.RoofBlue)
	Kit.block(model, "Terrace", Vector3.new(10, 0.5, 16), Kit.at(base, 8, 12, -1.5), P.StoneDark)
	for _, x in { 4, 12 } do
		Kit.block(
			model,
			"Rail",
			Vector3.new(0.3, 2, 16),
			Kit.at(base, x + 1, 13.2, -1.5),
			P.Glass,
			Enum.Material.Glass
		).Transparency =
			0.4
	end
	for _, x in { -9, 9 } do
		Kit.cylinder(model, "Column", 1.2, 11, Kit.at(base, x, 6.3, 8.5), P.White)
	end
	Kit.block(model, "Porch", Vector3.new(22, 0.6, 4), Kit.at(base, 0, 12, 8.5), P.White)
	Kit.decor(
		Kit.block(model, "Door", Vector3.new(3.4, 7, 0.3), Kit.at(base, 0, 4.3, 6.55), P.WoodDark)
	)
	frontWindow(model, Kit.at(base, 0, 0, -1.5), 16, -8, 6, 5, 5)
	frontWindow(model, Kit.at(base, 0, 0, -1.5), 16, 8, 6, 5, 5)
	frontWindow(model, Kit.at(base, -5, 0, -1.5), 14, 0, 16, 8, 4)
	-- Hồ bơi trước nhà
	Kit.block(model, "PoolRim", Vector3.new(12, 0.6, 7), Kit.at(base, 7, 0.3, 16), P.White)
	local water =
		Kit.block(model, "Pool", Vector3.new(10.6, 0.3, 5.6), Kit.at(base, 7, 0.55, 16), P.Water)
	Kit.decor(water)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.2
end

-- ───────────────────────────── Xe cộ theo bậc giá ─────────────────────────────

-- Xe đạp: rẻ nhất, khung mảnh
function Props.bicycle(parent: Instance, base: CFrame, color: Color3)
	local model = Kit.model(parent, "Bicycle")
	for _, forward in { 1.8, -1.8 } do
		local cf = Kit.at(base, 0, 1.1, forward) * CFrame.Angles(0, 0, math.pi / 2)
		Kit.cylinder(model, "Wheel", 2.2, 0.25, cf, Color3.fromRGB(34, 36, 42))
		Kit.decor(Kit.cylinder(model, "Rim", 1.5, 0.3, cf, P.Concrete, Enum.Material.Metal))
	end
	Kit.block(model, "Frame", Vector3.new(0.25, 0.25, 3.4), Kit.at(base, 0, 1.9, 0), color)
	Kit.block(
		model,
		"Down",
		Vector3.new(0.25, 0.25, 2.2),
		Kit.at(base, 0, 1.5, 0.7) * CFrame.Angles(math.rad(35), 0, 0),
		color
	)
	Kit.block(model, "SeatPost", Vector3.new(0.2, 1.2, 0.2), Kit.at(base, 0, 2.4, -1), P.MetalDark)
	Kit.block(
		model,
		"Seat",
		Vector3.new(0.6, 0.25, 1.1),
		Kit.at(base, 0, 3.05, -1),
		Color3.fromRGB(40, 40, 46)
	)
	Kit.block(model, "Stem", Vector3.new(0.2, 1.6, 0.2), Kit.at(base, 0, 2.6, 1.6), P.MetalDark)
	Kit.block(model, "Handle", Vector3.new(2, 0.2, 0.2), Kit.at(base, 0, 3.4, 1.6), P.MetalDark)
end

-- Xe tay ga: bánh nhỏ, yếm trước, sàn để chân
function Props.scooter(parent: Instance, base: CFrame, color: Color3)
	local model = Kit.model(parent, "Scooter")
	wheel(model, base, 0, 2.2, 1.7)
	wheel(model, base, 0, -2.2, 1.7)
	Kit.block(model, "Floor", Vector3.new(1.5, 0.4, 2.4), Kit.at(base, 0, 1.1, 0.2), color)
	Kit.block(model, "Rear", Vector3.new(1.6, 1.5, 2.6), Kit.at(base, 0, 1.9, -1.8), color)
	Kit.block(
		model,
		"Seat",
		Vector3.new(1.4, 0.45, 2.6),
		Kit.at(base, 0, 2.85, -1.6),
		Color3.fromRGB(50, 44, 40)
	)
	Kit.block(
		model,
		"Shield",
		Vector3.new(1.7, 2.6, 0.5),
		Kit.at(base, 0, 2.2, 1.9) * CFrame.Angles(math.rad(12), 0, 0),
		color
	)
	Kit.block(model, "Handle", Vector3.new(2.4, 0.3, 0.3), Kit.at(base, 0, 3.7, 1.5), P.MetalDark)
	Kit.decor(
		Kit.block(model, "Trim", Vector3.new(1.75, 0.2, 0.55), Kit.at(base, 0, 3.2, 1.75), P.White)
	)
	Kit.decor(
		Kit.ball(model, "Headlight", 0.8, Kit.at(base, 0, 2.9, 2.25), P.Lamp, Enum.Material.Neon)
	)
end

type CarSpec = {
	Name: string,
	Width: number,
	Length: number,
	Clearance: number, -- gầm cao bao nhiêu
	BodyHeight: number,
	CabinLength: number,
	CabinHeight: number,
	CabinForward: number,
	Wheel: number, -- đường kính bánh
	Trim: Color3?, -- nẹp mạ dọc thân (xe sang)
	RoofRack: boolean?,
	Spoiler: boolean?,
	Nose: boolean?, -- mũi vát thấp (siêu xe)
	Glow: Color3?, -- đèn gầm
}

-- Ô tô dựng theo thông số: dùng cho SUV, xe sang, siêu xe
local function buildCar(parent: Instance, base: CFrame, color: Color3, spec: CarSpec)
	local model = Kit.model(parent, spec.Name)
	local w, l, h = spec.Width, spec.Length, spec.BodyHeight
	local floor = spec.Clearance
	for _, side in { -1, 1 } do
		wheel(model, base, side * (w / 2 - 0.2), l / 2 - 2.6, spec.Wheel)
		wheel(model, base, side * (w / 2 - 0.2), -l / 2 + 2.6, spec.Wheel)
	end
	local bodyLength = if spec.Nose then l - 3 else l
	local bodyForward = if spec.Nose then -1.5 else 0
	Kit.block(
		model,
		"Body",
		Vector3.new(w, h, bodyLength),
		Kit.at(base, 0, floor + h / 2, bodyForward),
		color
	)
	if spec.Nose then
		-- Mũi vát: nêm thấp dần về phía trước
		Kit.wedge(
			model,
			"Nose",
			Vector3.new(w, h, 3),
			Kit.at(base, 0, floor + h / 2, l / 2 - 1.5),
			color
		)
	end
	local cabin = Kit.block(
		model,
		"Cabin",
		Vector3.new(w - 0.8, spec.CabinHeight, spec.CabinLength),
		Kit.at(base, 0, floor + h + spec.CabinHeight / 2, spec.CabinForward),
		Color3.fromRGB(70, 96, 120),
		Enum.Material.Glass
	)
	cabin.Transparency = 0.2
	cabin.Reflectance = 0.25
	Kit.decor(
		Kit.block(
			model,
			"Roof",
			Vector3.new(w - 0.6, 0.3, spec.CabinLength - 1),
			Kit.at(base, 0, floor + h + spec.CabinHeight + 0.15, spec.CabinForward),
			color
		)
	)
	local trim = spec.Trim
	if trim then
		for _, side in { -1, 1 } do
			Kit.decor(
				Kit.block(
					model,
					"Trim",
					Vector3.new(0.12, 0.25, bodyLength - 1),
					Kit.at(base, side * (w / 2 + 0.03), floor + h * 0.55, bodyForward),
					trim,
					Enum.Material.Metal
				)
			)
		end
		Kit.decor(
			Kit.block(
				model,
				"Grille",
				Vector3.new(w * 0.5, h * 0.55, 0.2),
				Kit.at(base, 0, floor + h * 0.5, l / 2 + 0.06),
				trim,
				Enum.Material.Metal
			)
		)
	end
	if spec.RoofRack then
		for _, side in { -1, 1 } do
			Kit.decor(
				Kit.block(
					model,
					"Rack",
					Vector3.new(0.25, 0.25, spec.CabinLength - 1.4),
					Kit.at(
						base,
						side * (w / 2 - 1),
						floor + h + spec.CabinHeight + 0.55,
						spec.CabinForward
					),
					P.MetalDark,
					Enum.Material.Metal
				)
			)
		end
	end
	local frontY = floor + h * 0.62
	local frontForward = if spec.Nose then l / 2 - 2.4 else l / 2 + 0.05
	for _, side in { -1, 1 } do
		Kit.decor(
			Kit.block(
				model,
				"Headlight",
				Vector3.new(1.3, 0.4, 0.25),
				Kit.at(base, side * (w / 2 - 1.1), frontY, frontForward),
				P.Lamp,
				Enum.Material.Neon
			)
		)
		Kit.decor(
			Kit.block(
				model,
				"TailLight",
				Vector3.new(1.5, 0.35, 0.2),
				Kit.at(base, side * (w / 2 - 1.1), frontY, -l / 2 - 0.05),
				Color3.fromRGB(235, 70, 70),
				Enum.Material.Neon
			)
		)
	end
	if spec.Spoiler then
		for _, side in { -1, 1 } do
			Kit.decor(
				Kit.block(
					model,
					"SpoilerPost",
					Vector3.new(0.3, 1.2, 0.3),
					Kit.at(base, side * (w / 2 - 1), floor + h + 0.6, -l / 2 + 0.9),
					P.MetalDark
				)
			)
		end
		Kit.decor(
			Kit.block(
				model,
				"Spoiler",
				Vector3.new(w + 0.4, 0.25, 1.6),
				Kit.at(base, 0, floor + h + 1.3, -l / 2 + 0.9),
				P.MetalDark
			)
		)
	end
	local glow = spec.Glow
	if glow then
		local strip = Kit.block(
			model,
			"Underglow",
			Vector3.new(w - 1, 0.1, l - 4),
			Kit.at(base, 0, floor - 0.25, 0),
			glow,
			Enum.Material.Neon
		)
		Kit.decor(strip)
		Kit.light(strip, glow, 10, 1.2)
	end
end

local CAR_SPECS: { [string]: CarSpec } = {
	suv = {
		Name = "SUV",
		Width = 6.6,
		Length = 13,
		Clearance = 1.5,
		BodyHeight = 2.6,
		CabinLength = 8.4,
		CabinHeight = 2.3,
		CabinForward = -1.2,
		Wheel = 3,
		RoofRack = true,
	},
	luxury_car = {
		Name = "LuxuryCar",
		Width = 6.4,
		Length = 15,
		Clearance = 1,
		BodyHeight = 1.9,
		CabinLength = 6.6,
		CabinHeight = 1.7,
		CabinForward = -0.8,
		Wheel = 2.4,
		Trim = Color3.fromRGB(226, 226, 232),
	},
	supercar = {
		Name = "Supercar",
		Width = 6.8,
		Length = 14,
		Clearance = 0.8,
		BodyHeight = 1.3,
		CabinLength = 4.6,
		CabinHeight = 1.2,
		CabinForward = -1,
		Wheel = 2.4,
		Spoiler = true,
		Nose = true,
		Glow = P.AuraGlow,
	},
}

-- Màu riêng cho xe cao cấp (xe thường dùng màu theo lô / bục)
local VEHICLE_FIXED_COLORS: { [string]: Color3 } = {
	luxury_car = Color3.fromRGB(28, 30, 40),
	supercar = Color3.fromRGB(240, 60, 60),
}

-- Dựng xe theo id trong Config.Assets; id chưa có kiểu riêng dùng ô tô thường
function Props.vehicle(parent: Instance, base: CFrame, id: string, color: Color3)
	local paint = VEHICLE_FIXED_COLORS[id] or color
	local spec = CAR_SPECS[id]
	if spec then
		buildCar(parent, base, paint, spec)
	elseif id == "bicycle" then
		Props.bicycle(parent, base, paint)
	elseif id == "motorbike" then
		Props.motorbike(parent, base, paint)
	elseif id == "scooter" then
		Props.scooter(parent, base, paint)
	else
		Props.car(parent, base, paint, id == "sportscar")
	end
end

-- ───────────────────────────── Nhà theo bậc giá ─────────────────────────────

-- Nhà cấp bốn: rộng hơn phòng trọ, có hiên và ống khói
function Props.houseCottage(parent: Instance, base: CFrame)
	local model = Kit.model(parent, "Cottage")
	Kit.block(model, "Base", Vector3.new(19, 0.6, 14), Kit.at(base, 0, 0.3, 0), P.Concrete)
	Kit.block(
		model,
		"Walls",
		Vector3.new(18, 8.5, 13),
		Kit.at(base, 0, 4.85, 0),
		Color3.fromRGB(236, 214, 170)
	)
	gable(model, base, 18, 13, 9.1, 4, P.RoofRed)
	Kit.block(model, "Chimney", Vector3.new(1.8, 5, 1.8), Kit.at(base, 5.5, 12, -2), P.StoneDark)
	Kit.block(model, "Porch", Vector3.new(8, 0.4, 3.4), Kit.at(base, -3, 0.8, 8), P.WoodLight)
	for _, x in { -6.5, 0.5 } do
		Kit.block(model, "PorchPost", Vector3.new(0.5, 6, 0.5), Kit.at(base, x, 3.8, 9.3), P.White)
	end
	Kit.block(model, "PorchRoof", Vector3.new(8.6, 0.4, 3.8), Kit.at(base, -3, 7, 8.2), P.RoofRed)
	Kit.decor(
		Kit.block(
			model,
			"Door",
			Vector3.new(2.8, 5.6, 0.3),
			Kit.at(base, -3, 3.4, 6.55),
			P.WoodDark
		)
	)
	frontWindow(model, base, 13, 4.5, 5, 3.6, 3)
	frontWindow(model, base, 13, -7, 5, 2, 3)
end

-- Nhà phố: hẹp, ba tầng, tầng trệt có cửa cuốn, ban công kính, sân thượng
function Props.houseTownhouse(parent: Instance, base: CFrame)
	local model = Kit.model(parent, "Townhouse")
	local accent = Color3.fromRGB(226, 120, 70)
	Kit.block(model, "Base", Vector3.new(14, 0.6, 19), Kit.at(base, 0, 0.3, 0), P.Concrete)
	Kit.block(model, "Walls", Vector3.new(13, 27, 18), Kit.at(base, 0, 14.1, 0), P.White)
	Kit.block(model, "Side", Vector3.new(2.4, 27, 18.2), Kit.at(base, -5.4, 14.1, 0), accent)
	Kit.block(model, "Roof", Vector3.new(14, 0.8, 19), Kit.at(base, 0, 28, 0), P.StoneDark)
	-- Sân thượng: lan can kính và giàn che
	local rail = Kit.block(
		model,
		"RoofRail",
		Vector3.new(13, 1.8, 0.3),
		Kit.at(base, 0, 29.3, 9.2),
		P.Glass,
		Enum.Material.Glass
	)
	rail.Transparency = 0.4
	Kit.block(model, "Pergola", Vector3.new(8, 0.4, 7), Kit.at(base, 1.5, 33, -4), P.WoodDark)
	for _, x in { -2, 5 } do
		Kit.block(
			model,
			"PergolaPost",
			Vector3.new(0.4, 4.6, 0.4),
			Kit.at(base, x, 30.7, -1),
			P.WoodDark
		)
		Kit.block(
			model,
			"PergolaPost",
			Vector3.new(0.4, 4.6, 0.4),
			Kit.at(base, x, 30.7, -7),
			P.WoodDark
		)
	end
	-- Tầng trệt: cửa cuốn và cửa chính
	Kit.decor(
		Kit.block(
			model,
			"Garage",
			Vector3.new(6, 6, 0.3),
			Kit.at(base, 2.6, 3.6, 9.05),
			P.MetalDark,
			Enum.Material.DiamondPlate
		)
	)
	Kit.decor(
		Kit.block(
			model,
			"Door",
			Vector3.new(2.4, 5.6, 0.3),
			Kit.at(base, -2.6, 3.4, 9.05),
			P.WoodDark
		)
	)
	for floor = 1, 2 do
		local y = 4 + floor * 9
		frontWindow(model, base, 18, 1.6, y, 7, 4.6)
		Kit.block(
			model,
			"Balcony",
			Vector3.new(9.4, 0.4, 2.4),
			Kit.at(base, 1.6, y - 3, 10),
			P.Concrete
		)
		local glass = Kit.block(
			model,
			"BalconyRail",
			Vector3.new(9.4, 1.8, 0.25),
			Kit.at(base, 1.6, y - 1.9, 11.1),
			P.Glass,
			Enum.Material.Glass
		)
		glass.Transparency = 0.4
	end
end

-- Nhà vườn: một tầng hình chữ L, mái ngói, hiên gỗ và vườn cây
function Props.houseGarden(parent: Instance, base: CFrame)
	local model = Kit.model(parent, "GardenHouse")
	local tile = Color3.fromRGB(190, 96, 64)
	Kit.block(model, "Base", Vector3.new(27, 0.6, 19), Kit.at(base, 0, 0.3, 0), P.Concrete)
	Kit.block(model, "Main", Vector3.new(26, 8, 11), Kit.at(base, 0, 4.6, -3.5), P.Cream)
	gable(model, Kit.at(base, 0, 0, -3.5), 26, 11, 8.6, 4, tile)
	-- Cánh nhà nhô ra phía trước (mái dốc xoay 90 độ)
	local wing = Kit.at(base, -8, 0, 4.5) * CFrame.Angles(0, math.pi / 2, 0)
	Kit.block(model, "Wing", Vector3.new(10, 8, 9), Kit.at(base, -8, 4.6, 4.5), P.Cream)
	gable(model, wing, 9, 10, 8.6, 3.4, tile)
	-- Hiên gỗ có giàn che
	Kit.block(
		model,
		"Deck",
		Vector3.new(15, 0.4, 7),
		Kit.at(base, 5, 0.8, 5.5),
		P.Wood,
		Enum.Material.WoodPlanks
	)
	for _, x in { -1.5, 5, 11.5 } do
		Kit.block(
			model,
			"DeckPost",
			Vector3.new(0.5, 7, 0.5),
			Kit.at(base, x, 4.3, 8.5),
			P.WoodDark
		)
	end
	for index = 0, 5 do
		Kit.decor(
			Kit.block(
				model,
				"Slat",
				Vector3.new(0.4, 0.3, 7.4),
				Kit.at(base, -1.5 + index * 2.6, 7.9, 5.4),
				P.WoodDark
			)
		)
	end
	Kit.decor(
		Kit.block(model, "Door", Vector3.new(3, 5.8, 0.3), Kit.at(base, 2, 3.5, 2.05), P.WoodDark)
	)
	frontWindow(model, Kit.at(base, 0, 0, -3.5), 11, 8, 5, 5, 3.6)
	frontWindow(model, Kit.at(base, -8, 0, 4.5), 9, 0, 5, 4, 3.6)
	Kit.block(model, "Chimney", Vector3.new(2, 5, 2), Kit.at(base, 9, 12, -5), P.StoneDark)
	-- Vườn trước nhà
	Props.tree(model, Kit.at(base, 11.5, 0, 12).Position, 0.8, 1)
	Props.flowerBed(model, Kit.at(base, -8, 0, 11.5), 8, 2.6, 71)
	Props.bush(model, Kit.at(base, 3, 0, 11.5).Position, 0.7)
end

-- Dinh thự: đắt nhất. Khối giữa hai tầng có hàng cột và trán tường, hai cánh, mái vòm, đài phun
function Props.houseMansion(parent: Instance, base: CFrame)
	local model = Kit.model(parent, "Mansion")
	local stone = Color3.fromRGB(240, 234, 220)
	local gold = Color3.fromRGB(232, 190, 90)
	local roof = Color3.fromRGB(58, 70, 100)
	Kit.block(model, "Base", Vector3.new(31, 1, 22), Kit.at(base, 0, 0.5, -3), P.Concrete)
	-- Hai cánh
	for _, side in { -1, 1 } do
		Kit.block(model, "Wing", Vector3.new(9, 14, 14), Kit.at(base, side * 10.5, 8, -4), stone)
		Kit.block(
			model,
			"WingRoof",
			Vector3.new(9.8, 0.8, 14.8),
			Kit.at(base, side * 10.5, 15.4, -4),
			roof
		)
		for floor = 0, 1 do
			frontWindow(model, Kit.at(base, side * 10.5, 0, -4), 14, 0, 5 + floor * 6.4, 4, 3.6)
		end
		Kit.decor(
			Kit.block(
				model,
				"WingBand",
				Vector3.new(9.2, 0.4, 0.3),
				Kit.at(base, side * 10.5, 14.6, 3.1),
				gold,
				Enum.Material.Metal
			)
		)
	end
	-- Khối giữa cao hơn, có mái vòm
	Kit.block(model, "Center", Vector3.new(13, 18, 17), Kit.at(base, 0, 10, -3), stone)
	gable(model, Kit.at(base, 0, 0, -3), 13, 17, 19, 3.6, roof)
	Kit.cylinder(model, "DomeBase", 7, 2, Kit.at(base, 0, 23, -3), stone)
	Kit.ball(model, "Dome", 6.6, Kit.at(base, 0, 24, -3), gold, Enum.Material.Metal)
	Kit.decor(
		Kit.cylinder(model, "Spire", 0.4, 3, Kit.at(base, 0, 28.6, -3), gold, Enum.Material.Metal)
	)
	-- Hàng cột và trán tường trước sảnh
	Kit.block(model, "Steps", Vector3.new(15, 0.6, 5), Kit.at(base, 0, 0.8, 8), P.Concrete)
	for _, x in { -6, -2, 2, 6 } do
		Kit.cylinder(
			model,
			"Column",
			1.2,
			14,
			Kit.at(base, x, 8.1, 8.6),
			P.White,
			Enum.Material.Marble
		)
	end
	Kit.block(model, "Entablature", Vector3.new(15, 1.2, 4.6), Kit.at(base, 0, 15.7, 7.6), P.White)
	Kit.wedge(model, "Pediment", Vector3.new(15, 2.8, 2.3), Kit.at(base, 0, 17.7, 8.75), P.White)
	Kit.wedge(
		model,
		"Pediment",
		Vector3.new(15, 2.8, 2.3),
		Kit.at(base, 0, 17.7, 6.45) * CFrame.Angles(0, math.pi, 0),
		P.White
	)
	Kit.decor(
		Kit.block(
			model,
			"Door",
			Vector3.new(4, 8, 0.3),
			Kit.at(base, 0, 5, 5.55),
			Color3.fromRGB(84, 52, 36),
			Enum.Material.Wood
		)
	)
	Kit.decor(
		Kit.block(
			model,
			"DoorTrim",
			Vector3.new(4.8, 0.5, 0.35),
			Kit.at(base, 0, 9.3, 5.6),
			gold,
			Enum.Material.Metal
		)
	)
	frontWindow(model, Kit.at(base, 0, 0, -3), 17, 0, 14, 5, 3.4)
	-- Sân trước: đài phun nhỏ và hai hàng cây cắt tỉa
	Kit.cylinder(
		model,
		"FountainBasin",
		7,
		1,
		Kit.at(base, 7, 0.5, 16),
		P.Stone,
		Enum.Material.Concrete
	)
	local water = Kit.cylinder(model, "FountainWater", 6, 0.2, Kit.at(base, 7, 1, 16), P.Water)
	Kit.decor(water)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.2
	Kit.cylinder(
		model,
		"FountainColumn",
		1,
		3,
		Kit.at(base, 7, 2, 16),
		P.White,
		Enum.Material.Marble
	)
	Kit.decor(
		Kit.ball(model, "FountainOrb", 1.6, Kit.at(base, 7, 4, 16), gold, Enum.Material.Metal)
	)
	-- Hai cây cảnh cạnh bậc thềm và một hàng dọc rào phải (bên trái là chỗ đỗ xe)
	local spots = { Kit.at(base, -8.5, 0, 9), Kit.at(base, 8.5, 0, 9) }
	for index = 0, 2 do
		table.insert(spots, Kit.at(base, 13.5, 0, 12 + index * 4))
	end
	for _, spot in spots do
		Kit.cylinder(model, "TopiaryTrunk", 0.5, 2, Kit.at(spot, 0, 1, 0), P.Trunk)
		Kit.decor(Kit.ball(model, "Topiary", 2.4, Kit.at(spot, 0, 3, 0), P.LeafDark))
	end
end

local HOUSE_BUILDERS: { [string]: (parent: Instance, base: CFrame) -> () } = {
	boarding = Props.houseBoarding,
	cottage = Props.houseCottage,
	apartment = Props.houseApartment,
	townhouse = Props.houseTownhouse,
	garden_house = Props.houseGarden,
	villa = Props.houseVilla,
	mansion = Props.houseMansion,
}

-- Dựng nhà theo id trong Config.Assets vào một Model riêng (trả về để có thể thu nhỏ khi trưng bày);
-- id chưa có kiểu riêng dùng phòng trọ
function Props.house(parent: Instance, base: CFrame, id: string): Model
	local holder = Kit.model(parent, "House_" .. id)
	local builder: (parent: Instance, base: CFrame) -> () = Props.houseBoarding
	local custom = HOUSE_BUILDERS[id]
	if custom then
		builder = custom
	end
	builder(holder, base)
	holder.WorldPivot = base
	return holder
end

return Props
