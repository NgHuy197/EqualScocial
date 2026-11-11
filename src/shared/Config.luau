--!strict
--[[
	Config.luau — NƠI DUY NHẤT chứa số liệu cân bằng và câu chữ hiển thị của game.

	Quy tắc:
	  * Không hard-code giá, lương, tốc độ tụt chỉ số... ở bất kỳ file nào khác.
	  * Thêm NGHỀ    : thêm một mục vào `Jobs`      (WorldBuilder tự xếp khối placeholder).
	  * Thêm TRẠM    : thêm một mục vào `Stations`.
	  * Thêm MÓN HÀNG: thêm một mục vào `Shops.<shopId>.Items`.
	  * Thêm LỚP HỌC : thêm một mục vào `Classes`   (WorldBuilder tự xếp khối, ghi kèm ngày mở).
	  * Thêm LOẠI QUÁI: thêm một mục vào `Monsters` (WorldBuilder tự xếp điểm xuất hiện theo `SpawnPoints`).
	  * Id (khoá) chỉ gồm chữ, số và dấu gạch dưới, tối đa 32 ký tự (xem Util/Validate.isId).
	  * Thang thời gian: các đại lượng "PerMinute" là mỗi phút THỰC; StatsService nhân với `Stats.TimeScale`.
]]

-- ───────────────────────────── Kiểu dữ liệu ─────────────────────────────

export type StatDef = {
	Name: string,
	Inverted: boolean?, -- true: càng cao càng xấu (Căng thẳng)
}

export type SkillDef = {
	Name: string,
}

export type Requirement = {
	Skill: string,
	Level: number,
}

export type JobDef = {
	Name: string,
	ActionText: string,
	BasePay: number,
	HoldDuration: number, -- giây giữ phím
	Skill: string, -- id kỹ năng được cộng XP và tăng lương
	StatDelta: { [string]: number }, -- thay đổi chỉ số sau mỗi lượt làm
	Requires: { Requirement }?, -- điều kiện mở khóa nghề (mọi mục đều phải đạt)
	XPReward: number?, -- mặc định JobRules.XPPerShift
	MinEnergy: number?, -- mặc định JobRules.MinEnergyToWork
	Color: Color3?, -- chỉ dùng cho khối placeholder
	Size: Vector3?,
}

export type ClassDef = {
	Name: string,
	ActionText: string,
	Skill: string, -- kỹ năng được cộng XP
	Days: { number }, -- các ngày lớp mở cửa (1 = Thứ Hai ... 7 = Chủ Nhật)
	HoldDuration: number,
	StatDelta: { [string]: number }, -- chi phí chỉ số mỗi buổi
	XPReward: number?, -- mặc định School.XPPerLesson
	Color: Color3?,
	Size: Vector3?,
}

export type MonsterDef = {
	Name: string,
	MaxHP: number,
	Damage: number, -- sát thương mỗi đòn lên người chơi
	AttackInterval: number, -- giây giữa hai đòn của quái
	AttackRange: number, -- studs, tính từ tâm quái
	Reward: number, -- tiền thưởng gốc khi bị hạ
	XPReward: number, -- XP gốc cho kỹ năng Combat.Skill
	StatDelta: { [string]: number }, -- chi phí chỉ số cho người tham gia hạ quái
	RespawnSeconds: number,
	SpawnPoints: number, -- số điểm xuất hiện trên bãi luyện tập (WorldBuilder tự xếp)
	Color: Color3,
	Size: Vector3,
}

export type AssetKind = "house" | "vehicle"

export type AssetDef = {
	Name: string,
	Kind: AssetKind,
	Price: number, -- giá thuê trả một lần khi thuê (không hoàn)
	FeePerCycle: number, -- phí duy trì mỗi chu kỳ AURA (trước hệ số chính sách)
	Fame: number, -- cộng vào Nổi tiếng khi đang thuê
	Stock: number?, -- chỉ tài sản hiếm: kho toàn cầu; chỉ có được qua đấu giá
}

export type AuraEventKind = "price" | "job_bonus" | "tax_holiday"

export type AuraEventDef = {
	Name: string,
	Kind: AuraEventKind,
	Weight: number, -- trọng số khi bốc thăm
	DurationSeconds: number,
	Category: string?, -- chỉ "price": nhóm hàng (ShopDef.Category)
	Multiplier: number?, -- "price": nhân giá; "job_bonus": nhân lương
	Announce: string, -- "job_bonus" có một %s cho tên nghề
}

export type StationDef = {
	Name: string,
	ActionText: string,
	HoldDuration: number,
	Effects: { [string]: number },
	DoneText: string,
	Color: Color3?,
	Size: Vector3?,
}

export type ItemKind = "consumable" | "permanent"

export type ItemDef = {
	Id: string,
	Name: string,
	Price: number,
	Kind: ItemKind, -- consumable: dùng ngay, cộng chỉ số | permanent: sở hữu vĩnh viễn, cộng Nổi tiếng
	Effects: { [string]: number }?, -- chỉ với consumable
	Fame: number?, -- chỉ với permanent
	Description: string?, -- bỏ trống thì UI tự sinh từ Effects/Fame
}

export type ShopDef = {
	Name: string,
	ActionText: string,
	Category: string, -- nhóm hàng cho sự kiện giá của AURA (ví dụ "food")
	Items: { ItemDef },
	Color: Color3?,
	Size: Vector3?,
}

-- ───────────────────────────── Chỉ số ─────────────────────────────

local Stats = {
	-- Thứ tự hiển thị trên HUD
	Order = { "Hunger", "Energy", "Hygiene", "Happiness", "Stress", "Health" },
	-- Các "nhu cầu" cơ bản (tụt theo thời gian)
	Needs = { "Hunger", "Energy", "Hygiene" },
	Defs = {
		Hunger = { Name = "Độ no" },
		Energy = { Name = "Năng lượng" },
		Hygiene = { Name = "Sạch sẽ" },
		Happiness = { Name = "Hạnh phúc" },
		Stress = { Name = "Căng thẳng", Inverted = true },
		Health = { Name = "Sức khỏe" },
	} :: { [string]: StatDef },

	Min = 0,
	Max = 100,

	TickSeconds = 5, -- chu kỳ cập nhật chỉ số
	-- Nhân tốc độ trôi thời gian của chỉ số. 1 = bình thường. Đặt 30–60 để test nhanh kiệt sức.
	TimeScale = 1,

	-- Chỉ số lúc bắt đầu: GIỐNG NHAU cho mọi người chơi
	Start = {
		Hunger = 100,
		Energy = 100,
		Hygiene = 100,
		Happiness = 70,
		Stress = 10,
		Health = 100,
	} :: { [string]: number },

	-- Chỉ số sau khi kiệt sức (mức an toàn: không nhu cầu nào dưới ngưỡng thấp)
	SafeReset = {
		Hunger = 60,
		Energy = 60,
		Hygiene = 60,
		Happiness = 50,
		Stress = 30,
		Health = 60,
	} :: { [string]: number },

	-- Mỗi phút các nhu cầu TỤT bấy nhiêu điểm (số dương = giảm)
	DecayPerMinute = {
		Hunger = 2,
		Energy = 1.5,
		Hygiene = 1,
	} :: { [string]: number },

	NeedLowThreshold = 30, -- nhu cầu dưới mức này bị coi là "thấp"

	-- Với MỖI nhu cầu thấp (số có dấu, đơn vị: điểm/phút):
	LowNeedHappinessPerMinute = -1,
	LowNeedStressPerMinute = 1,
	-- Khi KHÔNG có nhu cầu nào thấp:
	AllGoodHappinessPerMinute = 0.5,
	AllGoodStressPerMinute = -0.5,

	-- Sức khỏe (các hiệu ứng CỘNG DỒN với nhau, đơn vị: điểm/phút):
	StarvingHealthPerMinute = -3, -- Độ no hoặc Năng lượng bằng 0
	StressDangerHealthPerMinute = -1, -- Căng thẳng >= StressDangerThreshold
	StressDangerThreshold = 90,
	HealthRegenPerMinute = 1, -- mọi nhu cầu đều ổn (không cái nào thấp)
}

-- ───────────────────────────── Kinh tế ─────────────────────────────

local Economy = {
	StartingMoney = 100,
	MaxMoney = 1e12,
	ExhaustionLossPercent = 0.10, -- kiệt sức mất 10% tiền
	LogTransactions = false, -- true: in mọi giao dịch ra Output (debug)
}

-- Lý do giao dịch: AURA sau này dùng để đánh thuế / ghi log
local Reasons = {
	Job = "job",
	Shop = "shop",
	Exhaustion = "exhaustion",
	School = "school", -- học phí
	Monster = "monster", -- tiền thưởng hạ quái
	Defeat = "defeat", -- phí Bệnh xá khi thua trận
	AssetLease = "asset_lease", -- giá thuê tài sản (trả một lần)
	AssetRefund = "asset_refund", -- hoàn tiền khi trả lại tài sản (nếu ReturnRefundPercent > 0)
	Maintenance = "maintenance", -- phí duy trì tài sản mỗi chu kỳ
	Tax = "tax", -- thuế lũy tiến của AURA
	Auction = "auction", -- tiền đặt giá (khóa ngay khi đặt)
	AuctionFee = "auction_fee", -- phí đặt giá, không hoàn
	AuctionRefund = "auction_refund", -- hoàn tiền đặt giá khi bị vượt giá / đấu giá hủy
}

-- ───────────────────────────── Kỹ năng ─────────────────────────────

local Skills = {
	Order = { "Strength", "Communication", "Intelligence", "Dexterity" },
	Defs = {
		Strength = { Name = "Sức mạnh" },
		Communication = { Name = "Giao tiếp" },
		Intelligence = { Name = "Trí tuệ" },
		Dexterity = { Name = "Khéo tay" },
	} :: { [string]: SkillDef },

	StartLevel = 0,
	MaxLevel = 20,
	-- XP cần để lên cấp kế tiếp = XPBase + XPPerLevel * levelHiệnTại
	XPBase = 50,
	XPPerLevel = 25,
	-- Lương thực nhận = lươngGốc * (1 + PayBonusPerLevel * level)
	PayBonusPerLevel = 0.10,
}

-- ───────────────────────────── Nghề ─────────────────────────────

local JobRules = {
	XPPerShift = 10,
	MinEnergyToWork = 15, -- Năng lượng DƯỚI mức này thì không được làm
}

local Jobs: { [string]: JobDef } = {
	warehouse = {
		Name = "Bốc vác kho hàng",
		ActionText = "Bốc hàng",
		BasePay = 12,
		HoldDuration = 4,
		Skill = "Strength",
		StatDelta = { Energy = -6, Hunger = -4, Hygiene = -5, Stress = 3 },
		Color = Color3.fromRGB(160, 110, 60),
		Size = Vector3.new(16, 9, 12),
	},
	barista = {
		Name = "Pha chế cà phê",
		ActionText = "Pha cà phê",
		BasePay = 10,
		HoldDuration = 3,
		Skill = "Communication",
		StatDelta = { Energy = -4, Hunger = -3, Hygiene = -2, Stress = 4 },
		Color = Color3.fromRGB(120, 85, 70),
		Size = Vector3.new(14, 8, 10),
	},
	-- Hai nghề dưới đây chỉ mở khóa khi đã học kỹ năng ở trường (xem Classes)
	technician = {
		Name = "Kỹ thuật viên",
		ActionText = "Sửa chữa",
		BasePay = 22,
		HoldDuration = 5,
		Skill = "Dexterity",
		Requires = { { Skill = "Dexterity", Level = 3 } },
		StatDelta = { Energy = -7, Hunger = -4, Hygiene = -6, Stress = 4 },
		Color = Color3.fromRGB(90, 120, 150),
		Size = Vector3.new(14, 8, 12),
	},
	manager = {
		Name = "Quản lý",
		ActionText = "Điều hành",
		BasePay = 34,
		HoldDuration = 5,
		Skill = "Intelligence",
		Requires = { { Skill = "Intelligence", Level = 5 }, { Skill = "Communication", Level = 3 } },
		StatDelta = { Energy = -5, Hunger = -3, Hygiene = -1, Stress = 6 },
		Color = Color3.fromRGB(70, 85, 110),
		Size = Vector3.new(14, 8, 12),
	},
}

-- ───────────────────────────── Lịch trong game ─────────────────────────────
-- Ngày game tính từ giờ server (không lưu dữ liệu): ngày = floor(giờServer / DayLengthSeconds).
-- Nhờ vậy mọi máy chủ và mọi người chơi luôn cùng một ngày trong tuần.

local Calendar = {
	DayLengthSeconds = 600, -- 10 phút thực = 1 ngày game, 1 tuần = 70 phút
	DaysPerWeek = 7,
	DayNames = {
		"Thứ Hai",
		"Thứ Ba",
		"Thứ Tư",
		"Thứ Năm",
		"Thứ Sáu",
		"Thứ Bảy",
		"Chủ Nhật",
	},
	DayShortNames = { "T2", "T3", "T4", "T5", "T6", "T7", "CN" },
}

-- ───────────────────────────── Trường học ─────────────────────────────

local School = {
	-- Học phí mỗi buổi = TuitionPerLevel * (level kỹ năng hiện tại + 1)
	TuitionPerLevel = 10,
	XPPerLesson = 30, -- cao hơn làm nghề (JobRules.XPPerShift) nhưng không có lương
}

local Classes: { [string]: ClassDef } = {
	gym = {
		Name = "Phòng gym",
		ActionText = "Tập luyện",
		Skill = "Strength",
		Days = { 1, 3, 5 }, -- T2, T4, T6
		HoldDuration = 6,
		StatDelta = { Energy = -10, Hunger = -5, Hygiene = -6, Stress = 2 },
		Color = Color3.fromRGB(200, 90, 80),
		Size = Vector3.new(16, 9, 12),
	},
	softskills = {
		Name = "Lớp kỹ năng mềm",
		ActionText = "Học",
		Skill = "Communication",
		Days = { 2, 4, 6 }, -- T3, T5, T7
		HoldDuration = 6,
		StatDelta = { Energy = -6, Hunger = -3, Hygiene = -1, Stress = 3 },
		Color = Color3.fromRGB(230, 170, 70),
		Size = Vector3.new(16, 9, 12),
	},
	library = {
		Name = "Thư viện",
		ActionText = "Đọc sách",
		Skill = "Intelligence",
		Days = { 1, 2, 4, 5 }, -- T2, T3, T5, T6
		HoldDuration = 6,
		StatDelta = { Energy = -8, Hunger = -4, Hygiene = -1, Stress = 4 },
		Color = Color3.fromRGB(80, 110, 190),
		Size = Vector3.new(16, 9, 12),
	},
	workshop = {
		Name = "Xưởng thực hành",
		ActionText = "Thực hành",
		Skill = "Dexterity",
		Days = { 3, 6, 7 }, -- T4, T7, CN
		HoldDuration = 6,
		StatDelta = { Energy = -8, Hunger = -4, Hygiene = -4, Stress = 3 },
		Color = Color3.fromRGB(110, 160, 130),
		Size = Vector3.new(16, 9, 12),
	},
}

-- ───────────────────────────── Đánh quái ─────────────────────────────
-- Nhấn E vào quái để đánh (ProximityPrompt). Máu của người chơi trong trận là máu Humanoid,
-- tách riêng khỏi chỉ số Sức khỏe của hệ sinh tồn.

local Combat = {
	Skill = "Strength", -- kỹ năng quyết định sát thương và nhận XP
	-- Sát thương = round(BaseDamage * (1 + DamagePerStrengthLevel * level Sức mạnh))
	BaseDamage = 10,
	DamagePerStrengthLevel = 0.15,
	-- Chu kỳ giữa hai đòn = AttackInterval / tốc độ; tốc độ tăng tuyến tính từ MinSpeedFactor
	-- (Năng lượng 0) tới 1 (Năng lượng >= FullSpeedEnergy)
	AttackInterval = 1.0,
	FullSpeedEnergy = 50,
	MinSpeedFactor = 0.5,
	PlayerAttackRange = 10, -- studs (khoảng cách kích hoạt prompt)
	AttackRangeTolerance = 2, -- server cho phép lệch thêm chừng này khi kiểm tra tầm đánh
	MinAttackCooldown = 0.4, -- cooldown tối thiểu phía server của prompt đánh
	MonsterTickSeconds = 0.5, -- chu kỳ quái "suy nghĩ" (tìm mục tiêu, đánh, hồi sinh)

	-- Chia thưởng khi nhiều người cùng hạ một quái (chống cày theo nhóm)
	MinContribution = 0.10, -- phải gây >= 10% máu tối đa mới được tính là người tham gia
	-- Mỗi người nhận thưởng gốc * max(MinShare, 1 - SharePenaltyPerExtraPlayer * (số người - 1))
	SharePenaltyPerExtraPlayer = 0.25,
	MinShare = 0.25,

	-- Trần tiền kiếm từ quái (chống lạm phát). Vượt trần vẫn nhận XP, không nhận tiền.
	HourlyMoneyCap = 5000,
	CapWindowSeconds = 3600,

	-- Thua trận: chết trong DefeatWindowSeconds giây sau khi bị quái đánh => trả phí, hồi sinh ở Bệnh xá
	DefeatFee = 10,
	DefeatWindowSeconds = 6,
	-- Thời gian tối đa đợi engine đặt nhân vật mới vào điểm hồi sinh trước khi đưa tới Bệnh xá
	SpawnSettleSeconds = 2,
}

local Monsters: { [string]: MonsterDef } = {
	slime = {
		Name = "Slime Kẹo",
		MaxHP = 30,
		Damage = 5,
		AttackInterval = 2.0,
		AttackRange = 11,
		Reward = 12,
		XPReward = 12,
		StatDelta = { Energy = -6, Hunger = -4, Stress = 5 },
		RespawnSeconds = 15,
		SpawnPoints = 4,
		Color = Color3.fromRGB(255, 130, 190),
		Size = Vector3.new(4, 4, 4), -- quái là hình cầu: chỉ cạnh X được dùng làm đường kính
	},
	bear = {
		Name = "Gấu Bông",
		MaxHP = 120,
		Damage = 14,
		AttackInterval = 2.5,
		AttackRange = 11,
		Reward = 50,
		XPReward = 40,
		StatDelta = { Energy = -20, Hunger = -10, Stress = 14 },
		RespawnSeconds = 45,
		SpawnPoints = 2,
		Color = Color3.fromRGB(176, 128, 84),
		Size = Vector3.new(7, 7, 7),
	},
}

-- ───────────────────────────── Bảng xếp hạng ─────────────────────────────

local Leaderboard = {
	-- Tài sản ròng = tiền + tổng giá các món vĩnh viễn đang sở hữu
	StoreName = "EqualSocial_NetWorth_S1", -- hậu tố là SeasonId; mùa mới (v0.4) dùng store mới
	SeasonId = 1,
	TopCount = 50, -- số hạng đọc về và hiển thị trong panel
	RefreshSeconds = 60, -- chu kỳ đọc bảng xếp hạng
	PublishSeconds = 180, -- chu kỳ ghi tài sản ròng của từng người chơi (và khi rời game)
	BoardRows = 10, -- số hàng trên bảng 3D
	SuspiciousJump = 20000, -- tăng hơn mức này trong một chu kỳ ghi => ghi cảnh báo để xem xét
	PanelCloseDistance = 25, -- client tự đóng panel khi đi xa hơn (studs)
	OpenCooldown = 1, -- giây giữa hai lần mở bảng
}

-- ───────────────────────────── AURA (v0.3) ─────────────────────────────
-- Một "chu kỳ AURA" = một ngày game (Calendar.DayLengthSeconds). Chu kỳ tính từ giờ server nên mọi
-- máy chủ cùng nhịp. Phí duy trì chỉ tính khi người chơi đang online (không tính phí ngoại tuyến).

local Assets: { [string]: AssetDef } = {
	boarding = { Name = "Phòng trọ", Kind = "house", Price = 1000, FeePerCycle = 10, Fame = 20 },
	motorbike = { Name = "Xe máy", Kind = "vehicle", Price = 800, FeePerCycle = 8, Fame = 15 },
	apartment = { Name = "Căn hộ", Kind = "house", Price = 4000, FeePerCycle = 40, Fame = 60 },
	car = { Name = "Ô tô", Kind = "vehicle", Price = 5000, FeePerCycle = 60, Fame = 80 },
	-- Tài sản hiếm: kho giới hạn toàn cầu (registry DataStore), chỉ có được qua đấu giá
	villa = {
		Name = "Biệt thự",
		Kind = "house",
		Price = 20000,
		FeePerCycle = 200,
		Fame = 250,
		Stock = 3,
	},
	sportscar = {
		Name = "Xe thể thao",
		Kind = "vehicle",
		Price = 30000,
		FeePerCycle = 300,
		Fame = 400,
		Stock = 2,
	},
}

local AuraEvents: { [string]: AuraEventDef } = {
	food_crisis = {
		Name = "Khủng hoảng lương thực",
		Kind = "price",
		Category = "food",
		Multiplier = 1.5,
		Weight = 3,
		DurationSeconds = 600,
		Announce = "Giá đồ ăn tăng ×1,5 trong 10 phút.",
	},
	food_sale = {
		Name = "Khuyến mãi đồ ăn",
		Kind = "price",
		Category = "food",
		Multiplier = 0.7,
		Weight = 2,
		DurationSeconds = 600,
		Announce = "Giá đồ ăn giảm 30% trong 10 phút.",
	},
	labor_shortage = {
		Name = "Thiếu lao động",
		Kind = "job_bonus",
		Multiplier = 1.25,
		Weight = 3,
		DurationSeconds = 600,
		Announce = "Nghề %s đang thiếu người: lương +25%% trong 10 phút.", -- %% vì đi qua string.format
	},
	tax_holiday = {
		Name = "Ngày không thuế",
		Kind = "tax_holiday",
		Weight = 1,
		DurationSeconds = 600,
		Announce = "AURA miễn thuế ở kỳ thu thuế kế tiếp.",
	},
}

local Aura = {
	CycleSeconds = Calendar.DayLengthSeconds,
	GraceCycles = 3, -- nợ phí duy trì quá ngần này chu kỳ thì bị thu hồi
	TaxEveryCycles = 3, -- thu thuế mỗi 3 chu kỳ
	EventEveryCycles = 2, -- cứ 2 chu kỳ thử bắt đầu một sự kiện (mỗi lúc chỉ một sự kiện)
	AuctionEveryCycles = 6, -- cứ 6 chu kỳ mở một phiên đấu giá tài sản hiếm
	InflationEveryCycles = 3, -- cứ 3 chu kỳ kiểm tra lạm phát
	ActiveWorkerSeconds = 120, -- "đang làm nghề" = đã hoàn thành một lượt trong ngần này giây
	JobBonusMinPlayers = 2, -- sự kiện Thiếu lao động cần tối thiểu ngần này người chơi
	ReturnRefundPercent = 0, -- trả lại tài sản được hoàn bao nhiêu % giá thuê (0 = không hoàn)
	-- Thuế lũy tiến theo tài sản ròng: chỉ phần vượt ngưỡng của từng bậc chịu thuế suất của bậc đó
	TaxBrackets = {
		{ Upto = 5000, Rate = 0 },
		{ Upto = 20000, Rate = 0.01 },
		{ Upto = 100000, Rate = 0.03 },
		{ Upto = math.huge, Rate = 0.06 },
	},
	-- Bộ điều chỉnh lạm phát (theo từng server): đổi hệ số chính sách nhân vào phí duy trì và thuế
	Inflation = {
		TargetAvgMoney = 5000, -- tiền trung bình mục tiêu trên mỗi người chơi
		DeadBand = 0.10, -- lệch dưới ±10% so với mục tiêu thì giữ nguyên
		Gain = 0.25, -- bước = (trungBình / mụcTiêu - 1) * Gain
		MaxStep = 0.10, -- mỗi lần đổi tối đa ±10%
		MinMultiplier = 0.5,
		MaxMultiplier = 2.0,
		LogSize = 10, -- số dòng nhật ký công khai giữ lại
	},
	-- Phân loại giao dịch cho "Báo cáo AURA": in = tiền sinh ra, out = tiền bị hút, refund = hoàn lại
	FlowReasons = {
		job = "in",
		monster = "in",
		shop = "out",
		school = "out",
		defeat = "out",
		exhaustion = "out",
		asset_lease = "out",
		maintenance = "out",
		tax = "out",
		auction = "out",
		auction_fee = "out",
		auction_refund = "refund",
		asset_refund = "refund",
	} :: { [string]: string },
	BroadcastInterval = 0.5, -- giây giữa hai lần gửi trạng thái AURA cho client (khi có thay đổi)
	OpenCooldown = 1, -- giây giữa hai lần mở Trụ sở AURA
	PanelCloseDistance = 25, -- client tự đóng cửa sổ khi đi xa hơn (studs)
}

local Auction = {
	DurationSeconds = 120,
	StartPercent = 0.60, -- giá khởi điểm = StartPercent * giá thuê
	MinRaisePercent = 0.10, -- mỗi lần đặt giá phải cao hơn giá cao nhất ít nhất 10%
	BidFeePercent = 0.02, -- phí đặt giá, KHÔNG hoàn lại
	AntiSnipeWindowSeconds = 10, -- đặt giá trong ngần này giây cuối...
	AntiSnipeExtendSeconds = 10, -- ...thì phiên được cộng thêm ngần này giây
	CheckSeconds = 1, -- chu kỳ kiểm tra hết giờ
}

-- Registry toàn cầu cho tài sản hiếm: ai đang giữ cái nào (nhận bằng UpdateAsync nên không bị cấp trùng)
local AssetRegistry = {
	StoreName = "EqualSocial_AssetRegistry_S1", -- hậu tố là SeasonId
	Key = "registry",
	CacheSeconds = 30, -- đọc số lượng còn lại tối đa mỗi 30 giây
}

-- ───────────────────────────── Trạm miễn phí ─────────────────────────────

local Stations: { [string]: StationDef } = {
	shower = {
		Name = "Vòi tắm",
		ActionText = "Tắm",
		HoldDuration = 3,
		Effects = { Hygiene = 40 },
		DoneText = "Bạn vừa tắm xong, thấy sạch sẽ hẳn ra!",
		Color = Color3.fromRGB(120, 190, 235),
		Size = Vector3.new(8, 10, 8),
	},
	bed = {
		Name = "Giường",
		ActionText = "Ngủ",
		HoldDuration = 5,
		Effects = { Energy = 40, Stress = -10 },
		DoneText = "Bạn đã ngủ một giấc, người khoan khoái hơn nhiều.",
		Color = Color3.fromRGB(190, 130, 160),
		Size = Vector3.new(10, 3, 14),
	},
	bench = {
		Name = "Ghế công viên",
		ActionText = "Ngồi nghỉ",
		HoldDuration = 3,
		Effects = { Stress = -6, Happiness = 4 },
		DoneText = "Ngồi hóng gió một lát, đầu óc nhẹ nhõm hơn.",
		Color = Color3.fromRGB(110, 150, 95),
		Size = Vector3.new(10, 3, 4),
	},
}

-- ───────────────────────────── Cửa hàng ─────────────────────────────

local Shops: { [string]: ShopDef } = {
	restaurant = {
		Name = "Quán ăn",
		ActionText = "Vào quán ăn",
		Category = "food",
		Color = Color3.fromRGB(235, 140, 65),
		Size = Vector3.new(16, 9, 12),
		Items = {
			{
				Id = "banh_mi",
				Name = "Bánh mì",
				Price = 10,
				Kind = "consumable",
				Effects = { Hunger = 30 },
			},
			{
				Id = "pho",
				Name = "Phở",
				Price = 25,
				Kind = "consumable",
				Effects = { Hunger = 60, Happiness = 5 },
			},
			{
				Id = "nuoc_suoi",
				Name = "Nước suối",
				Price = 5,
				Kind = "consumable",
				Effects = { Hunger = 8, Energy = 5 },
			},
		},
	},
	fashion = {
		Name = "Cửa hàng thời trang",
		ActionText = "Vào cửa hàng",
		Category = "fashion",
		Color = Color3.fromRGB(155, 95, 205),
		Size = Vector3.new(16, 9, 12),
		Items = {
			{ Id = "sunglasses", Name = "Kính râm", Price = 200, Kind = "permanent", Fame = 5 },
			{
				Id = "gold_watch",
				Name = "Đồng hồ vàng",
				Price = 600,
				Kind = "permanent",
				Fame = 15,
			},
		},
	},
}

local ShopRules = {
	MaxBuyDistance = 15, -- server từ chối mua nếu người chơi cách cửa hàng xa hơn (studs)
	CloseDistance = 14, -- client tự đóng cửa sổ khi đi xa hơn (nhỏ hơn MaxBuyDistance một chút)
	OpenCooldown = 1, -- giây giữa hai lần mở cửa hàng
}

-- ───────────────────────────── ProximityPrompt (server) ─────────────────────────────

local Prompts = {
	MaxActivationDistance = 12, -- studs
	DistanceTolerance = 6, -- server cho phép lệch thêm chừng này khi kiểm tra khoảng cách
	-- Cooldown phía server = HoldDuration * CooldownFactor (chặn exploit bỏ qua thời gian giữ phím)
	CooldownFactor = 0.85,
	MinCooldown = 0.4,
	HoldNoticeThrottle = 1.5, -- giây giữa hai thông báo "không làm được" khi bắt đầu giữ phím
}

-- ───────────────────────────── Rate-limit RemoteFunction ─────────────────────────────

local RateLimits = {
	GetState = { Calls = 4, Window = 10 }, -- tối đa 4 lần / 10 giây
	ShopBuy = { Calls = 6, Window = 3 }, -- tối đa 6 lần / 3 giây
	GetLeaderboard = { Calls = 3, Window = 10 }, -- tối đa 3 lần / 10 giây
	GetAuraState = { Calls = 3, Window = 10 },
	AssetLease = { Calls = 4, Window = 5 },
	AssetReturn = { Calls = 4, Window = 5 },
	AuctionBid = { Calls = 4, Window = 5 },
}

local Replication = {
	SendRate = 5, -- số snapshot tối đa mỗi giây khi có thay đổi
	InitialStateTimeout = 30, -- giây chờ dữ liệu người chơi cho GetState
}

local Data = {
	-- v2: định dạng ProfileStore (có khóa phiên). Store v1 cũ (bảng thô) KHÔNG được đọc lại.
	StoreName = "EqualSocial_PlayerData_v2",
	KeyPrefix = "u_",
	SchemaVersion = 1,
	AutosaveSeconds = 120, -- chu kỳ autosave của ProfileStore (AUTO_SAVE_PERIOD)
}

-- ───────────────────────────── Thông báo & UI ─────────────────────────────

local Notify = {
	Kinds = { "info", "success", "warning", "error", "levelup", "aura" },
	DefaultKind = "info",
}

local UI = {
	ToastSeconds = 4,
	MaxToasts = 4,
	-- Thanh chỉ số: giá trị "tốt" quy đổi >= StatGood là xanh, >= StatWarn là vàng, còn lại đỏ.
	-- (Căng thẳng được đảo ngược: tốt = 100 - giá trị.)
	StatGood = 60,
	StatWarn = 30,
}

-- ───────────────────────────── Thế giới placeholder ─────────────────────────────

local World = {
	FolderName = "World",
	GroundSize = 320,
	Spacing = 26, -- khoảng cách giữa các khối cùng nhóm
	JobsOrigin = Vector3.new(-60, 0, 0), -- xếp dọc trục Z
	StationsOrigin = Vector3.new(60, 0, 0), -- xếp dọc trục Z
	ShopsOrigin = Vector3.new(0, 0, -70), -- xếp dọc trục X
	SchoolOrigin = Vector3.new(0, 0, 75), -- các lớp học xếp dọc trục X
	LeaderboardOrigin = Vector3.new(0, 0, 45), -- bảng xếp hạng 3D ở quảng trường
	LeaderboardSize = Vector3.new(28, 16, 1),
	MonsterZoneOrigin = Vector3.new(0, 0, 120), -- tâm Bãi luyện tập
	MonsterZoneRadius = 28, -- bán kính vòng điểm xuất hiện của quái
	MonsterZoneSize = 70, -- cạnh của mảng sàn đánh dấu bãi luyện tập
	InfirmaryOrigin = Vector3.new(-75, 0, 120), -- Bệnh xá (nơi hồi sinh khi thua trận)
	InfirmarySize = Vector3.new(14, 6, 14),
	InfirmaryDropHeight = 4, -- độ cao nhân vật xuất hiện phía trên Bệnh xá
	AuraOrigin = Vector3.new(65, 0, 55), -- Trụ sở AURA
	AuraSize = Vector3.new(18, 12, 14),
	DefaultSize = Vector3.new(12, 8, 12),
	DefaultColor = Color3.fromRGB(150, 150, 150),
	LabelMaxDistance = 90,
}

-- ───────────────────────────── Câu chữ (tiếng Việt) ─────────────────────────────
-- Các chuỗi có %s / %d được dùng với string.format. Giữ đúng thứ tự tham số khi sửa.

local Text = {
	-- Thế giới
	WelcomeSign = "Chào mừng đến Equal Social!\nAi cũng bắt đầu với %s. Mọi tài sản đều thuộc về AURA.",
	WorldHintHold = "Giữ [E]: %s",
	WorldHintTap = "Nhấn [E]: %s",

	WorldHintClass = "Giữ [E]: %s · Mở %s",
	MonsterZoneLabel = "BÃI LUYỆN TẬP",
	MonsterZoneHint = "Nhấn [E] vào quái để đánh",
	InfirmaryLabel = "BỆNH XÁ",
	InfirmaryHint = "Nơi hồi sinh khi bị quái đánh bại",
	LeaderboardLabel = "Bảng xếp hạng tài sản",
	LeaderboardPrompt = "Xem bảng",

	-- Nghề & kỹ năng
	TooTired = "Bạn quá mệt để làm việc (Năng lượng dưới %d). Hãy nghỉ ngơi trước!",
	JobDone = "%s: +%s · +%d XP %s",
	LevelUp = "Kỹ năng %s đã lên cấp %d!",
	JobLocked = "Chưa mở khóa nghề này. Cần %s.",
	RequirementItem = "%s Lv.%d",
	RequirementProgress = "%s Lv.%d (bạn đang Lv.%d)",
	JobTitleLocked = "%s (cần %s)",

	-- Trường học
	ClassClosed = "%s hôm nay nghỉ. Lớp mở vào: %s.",
	ClassSkillMaxed = "Bạn đã đạt cấp tối đa kỹ năng %s, không cần học thêm.",
	ClassNoMoney = "Học phí buổi này là %s, bạn không đủ tiền.",
	ClassDone = "Buổi học %s: -%s · +%d XP %s",

	-- Đánh quái
	AttackAction = "Đánh",
	MonsterKilled = "Hạ %s: +%s · +%d XP %s",
	MonsterKilledCapped = "Hạ %s: +%d XP %s (đã chạm trần tiền từ quái trong giờ này)",
	Defeated = "Bạn bị %s đánh bại! Phí Bệnh xá %s, bạn sẽ hồi sinh tại Bệnh xá.",

	-- Kiệt sức
	Exhausted = "Bạn đã kiệt sức và được đưa đi cấp cứu. Mất %s (%d%% số tiền).",

	-- Cửa hàng (server trả về)
	BoughtConsumable = "Đã mua %s (-%s).",
	BoughtPermanent = "Đã mua %s (-%s). Nổi tiếng +%d!",
	AlreadyOwned = "Bạn đã sở hữu món này rồi.",
	NotEnoughMoney = "Bạn không đủ tiền.",
	TooFarFromShop = "Bạn đang đứng quá xa cửa hàng.",
	TooFarFromAura = "Bạn đang đứng quá xa Trụ sở AURA.",
	InvalidRequest = "Yêu cầu không hợp lệ.",
	TooFast = "Bạn thao tác quá nhanh, hãy chậm lại một chút.",
	NoData = "Dữ liệu của bạn chưa sẵn sàng, vui lòng đợi giây lát.",
	ServerError = "Có lỗi xảy ra, vui lòng thử lại.",

	-- Dữ liệu
	DataLoadFailed = "Không thể tải dữ liệu của bạn. Vui lòng vào lại game sau ít phút.",
	DataSessionEnded = "Dữ liệu của bạn vừa được mở ở một máy chủ khác. Vui lòng vào lại game.",

	-- HUD (client)
	HudStats = "CHỈ SỐ",
	HudSkills = "KỸ NĂNG",
	HudFame = "Nổi tiếng: %s",
	HudNetWorth = "Tài sản ròng: %s",
	HudRank = "Hạng #%d",
	HudRankNone = "Ngoài top %d",
	HudDay = "Hôm nay: %s",
	SkillLevel = "Lv.%d",
	SkillLevelMax = "Lv.%d (Tối đa)",
	SkillXP = "%d/%d XP",

	-- Bảng xếp hạng 3D và panel (BoardRow dùng cho cả hai)
	BoardTitle = "BẢNG XẾP HẠNG TÀI SẢN",
	BoardRow = "%d. %s · %s",
	BoardLocalNote = "(chỉ gồm người chơi trong máy chủ này)",
	BoardEmpty = "Chưa có dữ liệu xếp hạng",
	UnknownPlayer = "Người chơi %d",
	LeaderboardTitle = "Bảng xếp hạng tài sản",
	LeaderboardYourRank = "Hạng của bạn: #%d · %s",
	LeaderboardYourRankNone = "Hạng của bạn: ngoài top %d · %s",
	LeaderboardUpdated = "Cập nhật %d giây trước",
	LeaderboardLocal = "Chưa kết nối DataStore xếp hạng: bảng chỉ gồm người chơi trong máy chủ này.",
	LeaderboardLoading = "Đang tải...",
	LeaderboardError = "Không tải được bảng xếp hạng, hãy thử lại.",
	LeaderboardAutoClosed = "Bạn đã đi xa nên bảng xếp hạng tự đóng.",
	LeaderboardClose = "Đóng",

	-- Cửa sổ cửa hàng (client)
	ShopClose = "Đóng",
	ShopBuy = "Mua %s",
	ShopOwned = "Đã sở hữu",
	ShopBuying = "Đang mua...",
	ShopTagPermanent = "Sở hữu vĩnh viễn",
	ShopFameLine = "Nổi tiếng +%d",
	ShopYourMoney = "Tiền của bạn: %s",
	ShopAutoClosed = "Bạn đã đi xa nên cửa hàng tự đóng.",
	ShopNetworkError = "Không kết nối được máy chủ, hãy thử lại.",

	-- ── AURA (v0.3) ──
	AuraLabel = "Trụ sở AURA",
	AuraPrompt = "Vào trụ sở",

	AssetLeased = "Đã thuê %s (-%s). Nổi tiếng +%d, phí duy trì %s mỗi chu kỳ.",
	AssetAlreadyLeased = "Bạn đang thuê tài sản này rồi.",
	AssetRareOnly = "Tài sản hiếm chỉ có thể có được qua đấu giá.",
	AssetNotLeased = "Bạn không thuê tài sản này.",
	AssetReturned = "Đã trả lại %s cho AURA.",
	AssetReturnedRefund = "Đã trả lại %s cho AURA, hoàn %s.",
	MaintenancePaid = "AURA thu phí duy trì: -%s.",
	MaintenanceLate = "Thiếu phí duy trì %s cho %s. Còn %d chu kỳ ân hạn trước khi bị thu hồi.",
	AssetRevoked = "AURA đã thu hồi %s vì nợ phí duy trì quá %d chu kỳ.",
	TaxCollected = "AURA thu thuế: -%s (tài sản ròng %s).",
	TaxHolidayApplied = "Ngày không thuế: AURA miễn thuế kỳ này.",
	EventStarted = "AURA · %s: %s",
	EventEnded = 'AURA: sự kiện "%s" đã kết thúc.',

	AuctionOpened = "AURA mở đấu giá %s. Giá khởi điểm %s, kéo dài %d giây.",
	AuctionNoStock = "AURA: không còn tài sản hiếm nào để đấu giá.",
	AuctionNone = "Không có phiên đấu giá nào đang diễn ra.",
	AuctionEnded = "Phiên đấu giá đã kết thúc.",
	AuctionBidOk = "Đã đặt giá %s cho %s (phí %s).",
	AuctionOutbid = "Bạn bị vượt giá ở phiên đấu giá %s, đã hoàn %s.",
	AuctionBidTooLow = "Giá tối thiểu hiện tại là %s.",
	AuctionLeading = "Bạn đang dẫn đầu phiên đấu giá này.",
	AuctionOwned = "Bạn đã thuê tài sản này rồi nên không thể đấu giá.",
	AuctionWon = "Bạn thắng đấu giá %s với %s! Nổi tiếng +%d.",
	AuctionWonAnnounce = "AURA: %s thắng đấu giá %s với %s.",
	AuctionNoWinner = "Phiên đấu giá %s kết thúc, không có ai đặt giá.",
	AuctionSoldOut = "Tài sản %s đã hết kho trong lúc đấu giá. Đã hoàn %s (phí đặt giá không hoàn).",
	AuctionCancelled = "Phiên đấu giá %s bị hủy vì người dẫn đầu rời máy chủ.",
	EscrowRefunded = "AURA hoàn %s tiền đặt giá chưa dùng.",

	InflationRaise = "AURA tăng phí duy trì và thuế thêm %d%% (tiền trung bình %s, mục tiêu %s).",
	InflationLower = "AURA giảm phí duy trì và thuế %d%% (tiền trung bình %s, mục tiêu %s).",

	HudAuraEvent = "AURA: %s · %s",
	HudAuraNone = "AURA: không có sự kiện",

	AuraTitle = "Trụ sở AURA",
	AuraClose = "Đóng",
	AuraTabAssets = "Tài sản",
	AuraTabAuction = "Đấu giá",
	AuraTabReport = "Báo cáo",
	AuraLoading = "Đang tải...",
	AuraError = "Không tải được dữ liệu AURA, hãy thử lại.",
	AuraAutoClosed = "Bạn đã đi xa nên Trụ sở AURA tự đóng.",

	AssetUpkeep = "Phí duy trì hiện tại: %s mỗi chu kỳ (1 chu kỳ = 1 ngày game)",
	AssetInfo = "%s · Giá thuê %s · Phí %s/chu kỳ · Nổi tiếng +%d",
	AssetLeaseButton = "Thuê %s",
	AssetReturnButton = "Trả lại",
	AssetRareButton = "Chỉ qua đấu giá",
	AssetDebt = "Nợ %d chu kỳ",
	AssetStock = "Kho còn %d/%d",
	AssetStockUnknown = "Kho: chưa rõ",
	AssetLeasedTag = "Đang thuê",
	AssetKindHouse = "Nhà",
	AssetKindVehicle = "Xe",

	AuctionCurrent = "Đang đấu giá: %s",
	AuctionBidLine = "Giá cao nhất: %s (%s)",
	AuctionNoBids = "Chưa có ai đặt giá. Giá khởi điểm: %s",
	AuctionTimeLeft = "Còn %s",
	AuctionBidButton = "Đặt giá %s",
	AuctionBidInfo = "Phí đặt giá %s (không hoàn) · cần tổng %s",
	AuctionNextAfter = "Phiên kế tiếp sau khoảng %s",
	AuctionFeeNote = "Phí đặt giá %d%% không hoàn lại; tiền thắng đấu giá bị AURA thu hồi.",

	ReportCycle = "Chu kỳ #%d · còn %s",
	ReportEvent = "Sự kiện: %s (còn %s)",
	ReportNoEvent = "Sự kiện: không có",
	ReportPolicy = "Hệ số chính sách (phí + thuế): ×%s",
	ReportTax = "Thuế kỳ tới: sau %s · dự kiến cho bạn: %s",
	ReportTaxExempt = "Thuế kỳ tới: được miễn (Ngày không thuế)",
	ReportAvg = "Tiền trung bình: %s (mục tiêu %s) · %d người chơi",
	ReportFlow = "Chu kỳ trước: tiền vào %s · tiền ra %s",
	ReportBrackets = "Biểu thuế theo tài sản ròng (mỗi %d chu kỳ):",
	ReportBracketUpto = "  Đến %s: %s%%",
	ReportBracketAbove = "  Trên %s: %s%%",
	ReportLog = "Nhật ký điều chỉnh của AURA:",
	ReportLogEmpty = "  (chưa có điều chỉnh nào)",
	ReportLocalRegistry = "Kho tài sản hiếm chỉ tính trong máy chủ này (chưa kết nối registry DataStore).",
}

local Config = {
	Version = "0.3.0",
	GameName = "Equal Social",
	AIName = "AURA",

	-- Tag CollectionService: dịch vụ gắn ProximityPrompt theo tag, nên model thật chỉ cần gắn tag + attribute
	Tags = {
		Job = "ES_Job",
		Station = "ES_Station",
		Shop = "ES_Shop",
		Class = "ES_Class", -- lớp học (attribute ClassId)
		Monster = "ES_Monster", -- quái đang sống (CombatService tự gắn, attribute MonsterId)
		MonsterSpawn = "ES_MonsterSpawn", -- điểm xuất hiện của quái (attribute MonsterId)
		Infirmary = "ES_Infirmary", -- nơi hồi sinh khi thua trận
		Leaderboard = "ES_Leaderboard", -- bảng xếp hạng 3D (LeaderboardService tự vẽ SurfaceGui)
		Aura = "ES_Aura", -- Trụ sở AURA (mở cửa sổ tài sản / đấu giá / báo cáo)
	},
	Attributes = {
		Job = "JobId",
		Station = "StationId",
		Shop = "ShopId",
		Class = "ClassId",
		Monster = "MonsterId",
	},

	Data = Data,
	Economy = Economy,
	Reasons = Reasons,
	Stats = Stats,
	Skills = Skills,
	JobRules = JobRules,
	Jobs = Jobs,
	Calendar = Calendar,
	School = School,
	Classes = Classes,
	Combat = Combat,
	Monsters = Monsters,
	Leaderboard = Leaderboard,
	Assets = Assets,
	AuraEvents = AuraEvents,
	Aura = Aura,
	Auction = Auction,
	AssetRegistry = AssetRegistry,
	Stations = Stations,
	Shops = Shops,
	ShopRules = ShopRules,
	Prompts = Prompts,
	RateLimits = RateLimits,
	Replication = Replication,
	Notify = Notify,
	UI = UI,
	World = World,
	Text = Text,
}

return Config
