--!strict
--[[
	Buildings.luau — công trình cho nghề, lớp học, trạm và cửa hàng.

	Mỗi hàm dựng nhận một `Site` (gốc trên mặt đất, mặt tiền theo LookVector, kích thước lấy từ Config)
	và TRẢ VỀ part làm điểm tương tác: WorldBuilder gắn tag + attribute + nhãn lên part đó, các service
	gắn ProximityPrompt theo tag. Nhờ vậy đổi hình dáng công trình không ảnh hưởng logic.

	Id chưa có kiểu riêng trong STYLES sẽ dùng `generic`, nên thêm nghề / lớp / trạm / cửa hàng mới
	trong Config vẫn tự có công trình trên map.
]]

local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)

local P = Kit.Palette

export type Site = {
	Id: string,
	Base: CFrame,
	Size: Vector3, -- (ngang, cao, sâu)
	Color: Color3,
	Title: string, -- chữ trên biển hiệu
}

type Builder = (model: Model, site: Site) -> BasePart

local Buildings = {}

local FOUNDATION = 0.5 -- độ cao nền; tường bắt đầu từ đây
local SIGN_OFFSET = 1.3 -- biển hiệu nhô ra trước mặt tiền ngần này studs

-- ───────────────────────────── Bộ phận dùng chung ─────────────────────────────

local function shell(
	model: Instance,
	base: CFrame,
	w: number,
	h: number,
	d: number,
	color: Color3,
	material: Enum.Material?
): Part
	Kit.block(
		model,
		"Foundation",
		Vector3.new(w + 1, FOUNDATION, d + 1),
		Kit.at(base, 0, FOUNDATION / 2, 0),
		P.StoneDark,
		Enum.Material.Concrete
	)
	return Kit.block(
		model,
		"Walls",
		Vector3.new(w, h, d),
		Kit.at(base, 0, FOUNDATION + h / 2, 0),
		color,
		material
	)
end

-- Mái dốc hai phía, nóc chạy ngang mặt tiền; `y` là độ cao chân mái
local function gableRoof(
	model: Instance,
	base: CFrame,
	w: number,
	d: number,
	y: number,
	rise: number,
	color: Color3,
	material: Enum.Material?
)
	local half = d / 2 + 0.9
	Kit.wedge(
		model,
		"Roof",
		Vector3.new(w + 1.8, rise, half),
		Kit.at(base, 0, y + rise / 2, half / 2),
		color,
		material
	)
	Kit.wedge(
		model,
		"Roof",
		Vector3.new(w + 1.8, rise, half),
		Kit.at(base, 0, y + rise / 2, -half / 2) * CFrame.Angles(0, math.pi, 0),
		color,
		material
	)
end

-- Mái bằng có gờ
local function flatRoof(
	model: Instance,
	base: CFrame,
	w: number,
	d: number,
	y: number,
	color: Color3
)
	Kit.block(model, "Roof", Vector3.new(w + 1, 0.6, d + 1), Kit.at(base, 0, y + 0.3, 0), color)
	Kit.decor(
		Kit.block(
			model,
			"RoofTrim",
			Vector3.new(w + 1.4, 0.5, d + 1.4),
			Kit.at(base, 0, y + 0.85, 0),
			P.White
		)
	)
end

-- Tấm phẳng áp lên một mặt tường (cửa, biển, mảng màu). `face` lấy từ Kit.face.
local function panel(
	model: Instance,
	face: CFrame,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	material: Enum.Material?
): Part
	local part =
		Kit.block(model, name, Vector3.new(w, h, 0.3), Kit.at(face, x, y, 0.1), color, material)
	Kit.decor(part)
	return part
end

local function window(model: Instance, face: CFrame, x: number, y: number, w: number, h: number)
	panel(model, face, "WindowFrame", x, y, w + 0.6, h + 0.6, P.White)
	local glass = Kit.block(
		model,
		"Window",
		Vector3.new(w, h, 0.3),
		Kit.at(face, x, y, 0.18),
		P.Glass,
		Enum.Material.Glass
	)
	Kit.decor(glass)
	glass.Reflectance = 0.2
end

local function door(model: Instance, face: CFrame, x: number, w: number, h: number, color: Color3)
	panel(model, face, "DoorFrame", x, FOUNDATION + h / 2 + 0.15, w + 0.6, h + 0.3, P.White)
	Kit.decor(
		Kit.block(
			model,
			"Door",
			Vector3.new(w, h, 0.3),
			Kit.at(face, x, FOUNDATION + h / 2, 0.2),
			color,
			Enum.Material.Wood
		)
	)
	Kit.decor(
		Kit.ball(
			model,
			"Knob",
			0.4,
			Kit.at(face, x + w / 2 - 0.5, FOUNDATION + h / 2, 0.45),
			Color3.fromRGB(235, 200, 100),
			Enum.Material.Metal
		)
	)
end

-- Mái hiên sọc hai màu, thấp dần ra phía trước
local function awning(
	model: Instance,
	face: CFrame,
	x: number,
	y: number,
	w: number,
	depth: number,
	colorA: Color3,
	colorB: Color3
)
	local stripes = math.max(2, math.floor(w / 1.4 + 0.5))
	local stripeWidth = w / stripes
	for index = 1, stripes do
		local offset = -w / 2 + stripeWidth * (index - 0.5)
		Kit.decor(
			Kit.block(
				model,
				"Awning",
				Vector3.new(stripeWidth, 0.25, depth),
				Kit.at(face, x + offset, y, depth / 2) * CFrame.Angles(math.rad(-14), 0, 0),
				if index % 2 == 1 then colorA else colorB
			)
		).CastShadow =
			true
	end
end

-- Biển hiệu trên mặt tiền
local function signBoard(
	model: Instance,
	face: CFrame,
	x: number,
	y: number,
	w: number,
	h: number,
	text: string,
	background: Color3,
	textColor: Color3,
	offset: number?
)
	-- Mặc định biển treo trước mép mái (mái nhô ra gần 1 stud) để không bị mái che chữ
	local forward = offset or SIGN_OFFSET
	local board = Kit.block(
		model,
		"SignBoard",
		Vector3.new(w, h, 0.5),
		Kit.at(face, x, y, forward),
		background
	)
	Kit.decor(board)
	Kit.decor(
		Kit.block(
			model,
			"SignFrame",
			Vector3.new(w + 0.5, h + 0.5, 0.3),
			Kit.at(face, x, y, forward - 0.14),
			P.MetalDark
		)
	)
	Kit.sign(board, Enum.NormalId.Front, text, { TextColor = textColor, Padding = 10 })
end

-- Quầy phục vụ: thân quầy (điểm tương tác) + mặt quầy
local function counter(
	model: Instance,
	base: CFrame,
	x: number,
	forward: number,
	w: number,
	bodyColor: Color3,
	topColor: Color3
): Part
	local body = Kit.block(
		model,
		"Counter",
		Vector3.new(w, 3.2, 1.8),
		Kit.at(base, x, 1.6, forward),
		bodyColor,
		Enum.Material.WoodPlanks
	)
	Kit.block(
		model,
		"CounterTop",
		Vector3.new(w + 0.6, 0.4, 2.4),
		Kit.at(base, x, 3.4, forward),
		topColor
	)
	return body
end

-- Bàn làm việc bốn chân, trả về mặt bàn
local function workbench(model: Instance, base: CFrame, x: number, forward: number, w: number): Part
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.block(
				model,
				"BenchLeg",
				Vector3.new(0.5, 2.8, 0.5),
				Kit.at(base, x + sx * (w / 2 - 0.4), 1.4, forward + sz * 0.8),
				P.MetalDark,
				Enum.Material.Metal
			)
		end
	end
	return Kit.block(
		model,
		"Workbench",
		Vector3.new(w, 0.6, 2.4),
		Kit.at(base, x, 3.1, forward),
		P.Wood,
		Enum.Material.WoodPlanks
	)
end

-- ───────────────────────────── Nghề ─────────────────────────────

local function warehouse(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, Color3.fromRGB(178, 152, 120), Enum.Material.Metal)
	gableRoof(model, base, w, d, FOUNDATION + h, 2.6, P.MetalDark, Enum.Material.Metal)

	-- Cửa cuốn lớn
	panel(model, front, "RollerFrame", -2.5, 4, 9, 7, P.MetalDark)
	Kit.decor(
		Kit.block(
			model,
			"RollerDoor",
			Vector3.new(8.2, 6.4, 0.3),
			Kit.at(front, -2.5, 3.8, 0.2),
			Color3.fromRGB(112, 120, 132),
			Enum.Material.DiamondPlate
		)
	)
	door(model, front, 5.6, 2.4, 5, P.WoodDark)
	signBoard(model, front, 0, h - 0.6, w - 3, 1.8, site.Title, Color3.fromRGB(60, 50, 40), P.Cream)

	-- Chồng thùng hàng trước cửa: thùng lớn là điểm tương tác
	local anchor = Props.crate(model, Kit.at(base, 4.6, 0, d / 2 + 3.2), 3.4)
	Props.crate(model, Kit.at(base, 1.4, 0, d / 2 + 3.6), 2.6)
	Props.crate(model, Kit.at(base, 4.4, 3.4, d / 2 + 3.3) * CFrame.Angles(0, 0.3, 0), 2.4)
	Kit.block(
		model,
		"Pallet",
		Vector3.new(5, 0.4, 4),
		Kit.at(base, -5, 0.2, d / 2 + 3),
		P.WoodLight,
		Enum.Material.WoodPlanks
	)
	Props.crate(model, Kit.at(base, -5, 0.4, d / 2 + 3), 2.8)
	return anchor
end

local function cafe(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, P.Cream)
	gableRoof(model, base, w, d, FOUNDATION + h, 3.2, P.RoofBrown)

	-- Ô cửa bán hàng + quầy + mái hiên
	panel(model, front, "ServiceWindow", 1.5, 5.2, 7, 3.4, Color3.fromRGB(70, 50, 44))
	awning(model, front, 1.5, 7.6, 8.4, 3.4, Color3.fromRGB(200, 80, 70), P.White)
	door(model, front, -4.8, 2.4, 5.2, P.WoodDark)
	signBoard(model, front, 0, h + 0.2, w - 4, 1.7, site.Title, P.WoodDark, P.Cream)

	local anchor =
		counter(model, base, 1.5, d / 2 + 1.1, 7, Color3.fromRGB(134, 94, 70), P.WoodLight)
	Kit.block(
		model,
		"CoffeeMachine",
		Vector3.new(1.8, 1.6, 1.4),
		Kit.at(base, 3.4, 4.4, d / 2 + 1.1),
		P.MetalDark,
		Enum.Material.Metal
	)
	for index = 0, 2 do
		Kit.decor(
			Kit.cylinder(
				model,
				"Cup",
				0.6,
				0.7,
				Kit.at(base, -0.6 + index * 0.9, 3.95, d / 2 + 1.3),
				P.White
			)
		)
	end
	Props.cafeTable(model, Kit.at(base, w / 2 + 4.2, 0, d / 2 - 1), Color3.fromRGB(200, 80, 70))
	return anchor
end

local function garage(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, Color3.fromRGB(104, 132, 160), Enum.Material.Metal)
	flatRoof(model, base, w, d, FOUNDATION + h, P.MetalDark)

	-- Khoang sửa xe (hốc tối) và cửa sổ
	panel(model, front, "Bay", -2.6, 3.8, 7.4, 6.6, Color3.fromRGB(36, 40, 50))
	panel(model, front, "BayStripe", -2.6, 7.3, 7.4, 0.5, Color3.fromRGB(240, 190, 60))
	window(model, front, 4.4, 5.2, 2.6, 2.6)
	signBoard(
		model,
		front,
		0,
		h + 0.1,
		w - 3,
		1.7,
		site.Title,
		Color3.fromRGB(240, 190, 60),
		P.MetalDark
	)

	local anchor = workbench(model, base, 4, d / 2 + 2.6, 5)
	Kit.block(
		model,
		"Toolbox",
		Vector3.new(2, 1.1, 1.2),
		Kit.at(base, 5, 3.95, d / 2 + 2.6),
		Color3.fromRGB(210, 70, 60)
	)
	Kit.decor(
		Kit.cylinder(
			model,
			"Gear",
			1.4,
			0.3,
			Kit.at(base, 2.8, 3.55, d / 2 + 2.6),
			P.Metal,
			Enum.Material.Metal
		)
	)
	-- Chồng lốp xe
	for index = 0, 2 do
		Kit.cylinder(
			model,
			"Tire",
			2.6,
			0.9,
			Kit.at(base, -6.2, 0.45 + index * 0.9, d / 2 + 2),
			Color3.fromRGB(34, 36, 42)
		)
	end
	return anchor
end

local function office(model: Model, site: Site): BasePart
	local base, w, d = site.Base, site.Size.X, site.Size.Z
	local h = site.Size.Y * 2 -- văn phòng hai tầng
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, Color3.fromRGB(86, 102, 130), Enum.Material.Concrete)
	flatRoof(model, base, w, d, FOUNDATION + h, P.StoneDark)

	-- Mặt kính hai tầng
	for floor = 0, 1 do
		for column = -1, 1 do
			if not (floor == 0 and column == 0) then
				window(model, front, column * 4.2, 4.4 + floor * 7.6, 3, 4.6)
			end
		end
	end
	panel(model, front, "GlassDoor", 0, 3.4, 3.4, 5.6, P.Glass, Enum.Material.Glass).Reflectance =
		0.25
	Kit.block(model, "Canopy", Vector3.new(6, 0.4, 3), Kit.at(front, 0, 6.8, 1.5), P.White)
	signBoard(model, front, 0, h + 0.1, w - 4, 1.7, site.Title, P.White, Color3.fromRGB(50, 64, 90))

	-- Bàn lễ tân trước sảnh
	local anchor = counter(model, base, 4.2, d / 2 + 3, 4.6, Color3.fromRGB(70, 82, 104), P.White)
	Kit.block(
		model,
		"Monitor",
		Vector3.new(1.8, 1.2, 0.2),
		Kit.at(base, 4.2, 4.5, d / 2 + 2.8),
		P.MetalDark
	)
	Kit.decor(
		Kit.block(
			model,
			"Screen",
			Vector3.new(1.6, 1, 0.05),
			Kit.at(base, 4.2, 4.5, d / 2 + 2.68),
			P.AuraGlow,
			Enum.Material.Neon
		)
	)
	Props.bush(model, Kit.at(base, -5.2, 0, d / 2 + 2.4).Position, 0.8)
	return anchor
end

-- ───────────────────────────── Lớp học ─────────────────────────────

local function gym(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, Color3.fromRGB(186, 92, 76), Enum.Material.Brick)
	flatRoof(model, base, w, d, FOUNDATION + h, P.StoneDark)
	window(model, front, -4.6, 5, 4.4, 3.6)
	window(model, front, 4.6, 5, 4.4, 3.6)
	door(model, front, 0, 2.8, 5.4, P.MetalDark)
	signBoard(
		model,
		front,
		0,
		h + 0.1,
		w - 4,
		1.7,
		site.Title,
		P.MetalDark,
		Color3.fromRGB(255, 120, 100)
	)

	-- Giàn tạ trước cửa: ghế tập là điểm tương tác
	local forward = d / 2 + 3
	local anchor = Kit.block(
		model,
		"WeightBench",
		Vector3.new(1.8, 1.4, 4.6),
		Kit.at(base, 4.6, 0.7, forward),
		Color3.fromRGB(40, 42, 50)
	)
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"RackPost",
			Vector3.new(0.4, 4.4, 0.4),
			Kit.at(base, 4.6 + side * 2, 2.2, forward - 1.4),
			P.Metal,
			Enum.Material.Metal
		)
		Kit.decor(
			Kit.cylinder(
				model,
				"Plate",
				2.2,
				0.5,
				Kit.at(base, 4.6 + side * 3, 4, forward - 1.4) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(34, 36, 42)
			)
		)
	end
	Kit.decor(
		Kit.cylinder(
			model,
			"Bar",
			0.25,
			7,
			Kit.at(base, 4.6, 4, forward - 1.4) * CFrame.Angles(0, 0, math.pi / 2),
			P.Concrete,
			Enum.Material.Metal
		)
	)
	-- Tạ tay xếp bên cạnh
	for index = 0, 2 do
		Kit.cylinder(
			model,
			"Dumbbell",
			1.2,
			0.8,
			Kit.at(base, -5.4 + index * 1.6, 0.6, forward) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(34, 36, 42)
		)
	end
	return anchor
end

local function classroom(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, Color3.fromRGB(240, 200, 110))
	gableRoof(model, base, w, d, FOUNDATION + h, 3.4, P.RoofRed)
	window(model, front, -4.8, 5, 3.6, 3.2)
	window(model, front, 4.8, 5, 3.6, 3.2)
	door(model, front, 0, 2.8, 5.4, P.WoodDark)
	signBoard(
		model,
		front,
		0,
		h + 0.1,
		w - 4,
		1.7,
		site.Title,
		P.White,
		Color3.fromRGB(190, 110, 30)
	)

	-- Bục phát biểu + bảng trắng ngoài sân
	local forward = d / 2 + 3
	local anchor = Kit.block(
		model,
		"Lectern",
		Vector3.new(2.4, 3.6, 1.6),
		Kit.at(base, 4.6, 1.8, forward),
		P.Wood,
		Enum.Material.Wood
	)
	Kit.decor(
		Kit.block(
			model,
			"LecternTop",
			Vector3.new(2.8, 0.3, 2),
			Kit.at(base, 4.6, 3.7, forward) * CFrame.Angles(math.rad(-12), 0, 0),
			P.WoodDark
		)
	)
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"BoardLeg",
			Vector3.new(0.3, 5.6, 0.3),
			Kit.at(base, -4.6 + side * 2.4, 2.8, forward - 0.6),
			P.Metal,
			Enum.Material.Metal
		)
	end
	Kit.block(
		model,
		"Whiteboard",
		Vector3.new(5.4, 3.2, 0.3),
		Kit.at(base, -4.6, 4, forward - 0.6),
		P.White
	)
	return anchor
end

local function library(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, Color3.fromRGB(214, 206, 190), Enum.Material.Concrete)
	gableRoof(model, base, w, d + 4, FOUNDATION + h, 3.2, P.RoofBlue)
	-- Hàng cột và bậc thềm
	Kit.block(
		model,
		"Steps",
		Vector3.new(w, 0.5, 3),
		Kit.at(base, 0, 0.25, d / 2 + 1.5),
		P.Concrete,
		Enum.Material.Concrete
	)
	for index = 0, 3 do
		Kit.cylinder(
			model,
			"Column",
			1.1,
			h,
			Kit.at(base, -w / 2 + 1.4 + index * (w - 2.8) / 3, FOUNDATION + h / 2, d / 2 + 2),
			P.White,
			Enum.Material.Concrete
		)
	end
	Kit.block(
		model,
		"Lintel",
		Vector3.new(w, 0.8, 3.2),
		Kit.at(base, 0, FOUNDATION + h - 0.4, d / 2 + 1.6),
		P.White,
		Enum.Material.Concrete
	)
	door(model, front, 0, 3, 5.8, P.WoodDark)
	window(model, front, -5, 5, 2.4, 4)
	window(model, front, 5, 5, 2.4, 4)
	signBoard(
		model,
		front,
		0,
		h - 1.4,
		7,
		1.5,
		site.Title,
		Color3.fromRGB(50, 70, 120),
		P.White,
		0.3
	)

	-- Bàn đọc có chồng sách
	local forward = d / 2 + 5.6
	local anchor = workbench(model, base, 4.4, forward, 4.6)
	local bookColors = {
		Color3.fromRGB(200, 70, 70),
		Color3.fromRGB(70, 130, 200),
		Color3.fromRGB(90, 170, 110),
		Color3.fromRGB(230, 180, 70),
	}
	for index, color in bookColors do
		Kit.decor(
			Kit.block(
				model,
				"Book",
				Vector3.new(1.6, 0.35, 1.2),
				Kit.at(base, 3.6, 3.4 + index * 0.36, forward) * CFrame.Angles(0, index * 0.25, 0),
				color
			)
		)
	end
	Kit.decor(
		Kit.block(
			model,
			"OpenBook",
			Vector3.new(1.8, 0.15, 1.3),
			Kit.at(base, 5.6, 3.5, forward),
			P.White
		)
	)
	return anchor
end

local function trainingWorkshop(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, Color3.fromRGB(118, 164, 136), Enum.Material.Metal)
	-- Mái răng cưa kiểu nhà xưởng
	local teeth = 3
	local tooth = (d + 1) / teeth
	for index = 1, teeth do
		Kit.wedge(
			model,
			"Roof",
			Vector3.new(w + 1, 2.4, tooth),
			Kit.at(base, 0, FOUNDATION + h + 1.2, (d + 1) / 2 - tooth * (index - 0.5)),
			P.MetalDark,
			Enum.Material.Metal
		)
	end
	panel(model, front, "BigDoor", -3, 3.8, 6, 6.6, Color3.fromRGB(70, 96, 84))
	panel(model, front, "DoorSplit", -3, 3.8, 0.3, 6.6, P.MetalDark)
	window(model, front, 4.8, 5.2, 3, 2.8)
	signBoard(
		model,
		front,
		0,
		h + 0.1,
		w - 4,
		1.7,
		site.Title,
		P.MetalDark,
		Color3.fromRGB(150, 230, 180)
	)

	local forward = d / 2 + 2.8
	local anchor = workbench(model, base, 4.6, forward, 5.2)
	Kit.block(
		model,
		"Vise",
		Vector3.new(1, 1, 1.2),
		Kit.at(base, 6.2, 3.9, forward),
		Color3.fromRGB(60, 90, 160),
		Enum.Material.Metal
	)
	Kit.decor(
		Kit.block(
			model,
			"Plank",
			Vector3.new(3.4, 0.3, 1),
			Kit.at(base, 3.8, 3.55, forward) * CFrame.Angles(0, 0.2, 0),
			P.WoodLight,
			Enum.Material.WoodPlanks
		)
	)
	Kit.block(
		model,
		"SawHorse",
		Vector3.new(4, 2.4, 1),
		Kit.at(base, -5, 1.2, forward),
		P.Wood,
		Enum.Material.Wood
	)
	return anchor
end

-- ───────────────────────────── Trạm miễn phí ─────────────────────────────

local function shower(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local tile = Color3.fromRGB(190, 226, 240)
	Kit.block(model, "Tray", Vector3.new(w, 0.5, d), Kit.at(base, 0, 0.25, 0), P.White)
	Kit.block(
		model,
		"BackWall",
		Vector3.new(w, h - 2, 0.6),
		Kit.at(base, 0, h / 2 - 0.5, -d / 2 + 0.3),
		tile
	)
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"SideWall",
			Vector3.new(0.6, h - 2, d),
			Kit.at(base, side * (w / 2 - 0.3), h / 2 - 0.5, 0),
			tile
		)
	end
	Kit.block(
		model,
		"Roof",
		Vector3.new(w + 1, 0.5, d + 1),
		Kit.at(base, 0, h - 1.5, 0),
		P.RoofBlue
	)
	-- Ống nước và vòi sen
	Kit.decor(
		Kit.cylinder(
			model,
			"Pipe",
			0.35,
			6.4,
			Kit.at(base, 0, 3.7, -d / 2 + 0.9),
			P.Metal,
			Enum.Material.Metal
		)
	)
	Kit.decor(
		Kit.block(
			model,
			"Arm",
			Vector3.new(0.3, 0.3, 2),
			Kit.at(base, 0, 6.9, -d / 2 + 1.8),
			P.Metal,
			Enum.Material.Metal
		)
	)
	local head = Kit.cylinder(
		model,
		"ShowerHead",
		1.4,
		0.3,
		Kit.at(base, 0, 6.7, -d / 2 + 2.8),
		P.Metal,
		Enum.Material.Metal
	)
	Kit.decor(head)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(190, 230, 255))
	emitter.Size = NumberSequence.new(0.22)
	emitter.Transparency = NumberSequence.new(0.3, 0.9)
	emitter.Lifetime = NumberRange.new(0.5, 0.7)
	emitter.Rate = 40
	emitter.Speed = NumberRange.new(10, 12)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.EmissionDirection = Enum.NormalId.Left -- trục trụ nằm theo X cục bộ; Left = hướng xuống
	emitter.Parent = head
	local sign = Kit.block(
		model,
		"SignBoard",
		Vector3.new(w, 1.5, 0.4),
		Kit.at(base, 0, h - 0.4, d / 2),
		P.RoofBlue
	)
	Kit.decor(sign)
	Kit.sign(sign, Enum.NormalId.Front, site.Title, { TextColor = P.White, Padding = 8 })
	return Kit.zone(model, "ShowerZone", Vector3.new(w - 2, 5, d - 2), Kit.at(base, 0, 3, 0.5))
end

local function restPavilion(model: Model, site: Site): BasePart
	local base, w, d = site.Base, site.Size.X, site.Size.Z
	local roofY = 8
	Kit.block(
		model,
		"Deck",
		Vector3.new(w + 2, 0.5, d + 2),
		Kit.at(base, 0, 0.25, 0),
		P.WoodLight,
		Enum.Material.WoodPlanks
	)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.block(
				model,
				"Post",
				Vector3.new(0.8, roofY, 0.8),
				Kit.at(base, sx * (w / 2 + 0.4), roofY / 2 + 0.5, sz * (d / 2 + 0.4)),
				P.WoodDark,
				Enum.Material.Wood
			)
		end
	end
	gableRoof(model, base, w + 1.6, d + 1.6, roofY + 0.5, 3, P.RoofTeal)
	Kit.block(
		model,
		"BackScreen",
		Vector3.new(w + 1.6, 5, 0.4),
		Kit.at(base, 0, 3, -d / 2 - 0.4),
		P.WoodLight,
		Enum.Material.WoodPlanks
	)
	-- Giường: khung gỗ, nệm (điểm tương tác), gối và chăn
	Kit.block(
		model,
		"BedFrame",
		Vector3.new(5.4, 1.2, 9.4),
		Kit.at(base, 0, 1.1, -0.6),
		P.Wood,
		Enum.Material.Wood
	)
	Kit.block(
		model,
		"Headboard",
		Vector3.new(5.4, 3, 0.5),
		Kit.at(base, 0, 2, -5.2),
		P.WoodDark,
		Enum.Material.Wood
	)
	local mattress =
		Kit.block(model, "Mattress", Vector3.new(5, 0.8, 9), Kit.at(base, 0, 2.1, -0.6), P.White)
	Kit.decor(
		Kit.block(
			model,
			"Blanket",
			Vector3.new(5.1, 0.3, 5.4),
			Kit.at(base, 0, 2.6, 1.2),
			site.Color
		)
	)
	Kit.decor(
		Kit.block(model, "Pillow", Vector3.new(3.4, 0.6, 1.6), Kit.at(base, 0, 2.8, -4), P.Cream)
	)
	-- Tủ đầu giường có đèn ngủ
	Kit.block(
		model,
		"Nightstand",
		Vector3.new(2, 2.2, 2),
		Kit.at(base, 4, 1.6, -4),
		P.Wood,
		Enum.Material.Wood
	)
	local lamp =
		Kit.ball(model, "NightLamp", 1.1, Kit.at(base, 4, 3.3, -4), P.Lamp, Enum.Material.Neon)
	Kit.decor(lamp)
	Kit.light(lamp, P.Lamp, 14, 1)
	local sign = Kit.block(
		model,
		"SignBoard",
		Vector3.new(6, 1.4, 0.4),
		Kit.at(base, 0, roofY - 0.4, d / 2 + 0.6),
		P.RoofTeal
	)
	Kit.decor(sign)
	Kit.sign(sign, Enum.NormalId.Front, site.Title, { TextColor = P.White, Padding = 8 })
	return mattress
end

local function parkBench(model: Model, site: Site): BasePart
	local base, w = site.Base, site.Size.X
	Kit.decor(
		Kit.block(
			model,
			"Paving",
			Vector3.new(w + 4, 0.2, 8),
			Kit.at(base, 0, 0.05, 0.5),
			P.Plaza,
			Enum.Material.Cobblestone
		)
	)
	local seat = Props.bench(model, base)
	seat.Size = Vector3.new(7.6, 0.4, 2.2)
	Props.tree(model, Kit.at(base, 0, 0, -5).Position, 1.25, 1)
	Props.flowerBed(model, Kit.at(base, -6.4, 0, 0), 3, 3, 7)
	Props.flowerBed(model, Kit.at(base, 6.4, 0, 0), 3, 3, 11)
	return seat
end

-- ───────────────────────────── Cửa hàng ─────────────────────────────

local function restaurant(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, Color3.fromRGB(240, 170, 100))
	gableRoof(model, base, w, d, FOUNDATION + h, 3.4, P.RoofRed)
	panel(model, front, "ServiceWindow", -1.5, 5.2, 9, 3.4, Color3.fromRGB(84, 50, 38))
	awning(
		model,
		front,
		-1.5,
		7.7,
		10.4,
		3.6,
		Color3.fromRGB(226, 70, 56),
		Color3.fromRGB(250, 214, 110)
	)
	door(model, front, 5.8, 2.4, 5.2, Color3.fromRGB(120, 60, 44))
	signBoard(
		model,
		front,
		0,
		h + 0.2,
		w - 4,
		1.8,
		site.Title,
		Color3.fromRGB(170, 44, 40),
		Color3.fromRGB(255, 226, 150)
	)

	local anchor =
		counter(model, base, -1.5, d / 2 + 1.1, 9, Color3.fromRGB(150, 84, 58), P.WoodLight)
	-- Nồi nước dùng và mấy tô phở
	Kit.cylinder(
		model,
		"Pot",
		2.2,
		1.8,
		Kit.at(base, -4.4, 4.5, d / 2 + 1.1),
		P.Metal,
		Enum.Material.Metal
	)
	local broth = Kit.cylinder(
		model,
		"Broth",
		1.9,
		0.1,
		Kit.at(base, -4.4, 5.38, d / 2 + 1.1),
		Color3.fromRGB(226, 170, 90)
	)
	Kit.decor(broth)
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Color3.new(1, 1, 1))
	steam.Size = NumberSequence.new(0.5, 1.4)
	steam.Transparency = NumberSequence.new(0.6, 1)
	steam.Lifetime = NumberRange.new(1.2, 1.8)
	steam.Rate = 6
	steam.Speed = NumberRange.new(1.5, 2.5)
	steam.EmissionDirection = Enum.NormalId.Right -- trục trụ theo X cục bộ; Right = hướng lên
	steam.Parent = broth
	for index = 0, 2 do
		Kit.decor(
			Kit.cylinder(
				model,
				"Bowl",
				1.1,
				0.5,
				Kit.at(base, -1.6 + index * 1.5, 3.85, d / 2 + 1.3),
				P.White
			)
		)
	end
	-- Đèn lồng đỏ hai bên hiên
	for _, side in { -1, 1 } do
		local lantern = Kit.cylinder(
			model,
			"Lantern",
			1.1,
			1.4,
			Kit.at(front, -1.5 + side * 5.6, 6.4, 3.4),
			Color3.fromRGB(226, 60, 50),
			Enum.Material.Neon
		)
		Kit.decor(lantern)
	end
	Props.cafeTable(model, Kit.at(base, -w / 2 - 4.2, 0, d / 2 - 1), Color3.fromRGB(226, 70, 56))
	return anchor
end

local function boutique(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	local accent = Color3.fromRGB(160, 100, 215)
	shell(model, base, w, h, d, P.White)
	flatRoof(model, base, w, d, FOUNDATION + h, accent)
	panel(model, front, "Band", 0, h - 0.6, w, 1.6, accent)
	-- Hai tủ kính trưng bày và cửa kính
	for _, side in { -1, 1 } do
		window(model, front, side * 5, 4.2, 4.6, 5)
		-- Ma-nơ-canh trên bục ngoài hiên
		local x = side * 5
		local forward = d / 2 + 1.6
		Kit.cylinder(model, "Podium", 2.4, 0.5, Kit.at(base, x, 0.25, forward), P.Concrete)
		Kit.decor(
			Kit.block(
				model,
				"Torso",
				Vector3.new(1.6, 2.6, 0.9),
				Kit.at(base, x, 3, forward),
				if side == -1 then Color3.fromRGB(240, 120, 160) else Color3.fromRGB(90, 170, 230)
			)
		)
		Kit.decor(
			Kit.block(
				model,
				"Legs",
				Vector3.new(1.4, 1.4, 0.8),
				Kit.at(base, x, 1.1, forward),
				Color3.fromRGB(50, 54, 70)
			)
		)
		Kit.decor(Kit.ball(model, "Head", 1.1, Kit.at(base, x, 4.9, forward), P.Cream))
	end
	panel(model, front, "GlassDoor", 0, 3.5, 3, 5.8, P.Glass, Enum.Material.Glass).Reflectance =
		0.25
	awning(model, front, 0, 7.6, 5, 2.6, accent, P.White)
	signBoard(
		model,
		front,
		0,
		h + 0.3,
		w - 5,
		1.8,
		site.Title,
		P.MetalDark,
		Color3.fromRGB(230, 200, 255)
	)

	-- Quầy thu ngân nhỏ trước cửa
	local anchor = counter(model, base, 0, d / 2 + 4, 3.6, accent, P.White)
	Kit.decor(
		Kit.block(
			model,
			"Register",
			Vector3.new(1.2, 0.8, 1),
			Kit.at(base, 0.8, 4, d / 2 + 4),
			P.MetalDark
		)
	)
	return anchor
end

-- ───────────────────────────── Mặc định ─────────────────────────────

local function generic(model: Model, site: Site): BasePart
	local base, w, h, d = site.Base, site.Size.X, site.Size.Y, site.Size.Z
	local front = Kit.face(base, w, d, "front")
	shell(model, base, w, h, d, site.Color)
	gableRoof(model, base, w, d, FOUNDATION + h, math.max(2, h * 0.35), P.RoofBrown)
	door(model, front, 0, 2.6, math.min(5.4, h - 1), P.WoodDark)
	if w >= 10 and h >= 6 then
		window(model, front, -w / 3, h * 0.6, 2.6, 2.6)
		window(model, front, w / 3, h * 0.6, 2.6, 2.6)
	end
	signBoard(model, front, 0, h + 0.1, math.max(4, w - 4), 1.6, site.Title, P.MetalDark, P.White)
	return counter(model, base, math.min(4, w / 3), d / 2 + 2.6, 4, P.Wood, P.WoodLight)
end

-- Kiểu công trình theo id trong Config; id không có ở đây dùng `generic`
local STYLES: { [string]: Builder } = {
	warehouse = warehouse,
	barista = cafe,
	technician = garage,
	manager = office,
	gym = gym,
	softskills = classroom,
	library = library,
	workshop = trainingWorkshop,
	shower = shower,
	bed = restPavilion,
	bench = parkBench,
	restaurant = restaurant,
	fashion = boutique,
}

-- Dựng công trình cho `site` vào `parent`, trả về part làm điểm tương tác
function Buildings.Build(parent: Instance, site: Site): BasePart
	local model = Kit.model(parent, site.Id)
	local builder: Builder = generic
	local styled = STYLES[site.Id]
	if styled then
		builder = styled
	end
	local anchor = builder(model, site)
	model.PrimaryPart = anchor
	return anchor
end

return Buildings
