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

return Props
