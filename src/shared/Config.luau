--!strict
--[[
	Config.luau — NƠI DUY NHẤT chứa số liệu cân bằng và câu chữ hiển thị của game.

	Quy tắc:
	  * Không hard-code giá, lương, tốc độ tụt chỉ số... ở bất kỳ file nào khác.
	  * Thêm NGHỀ    : thêm một mục vào `Jobs`      (WorldBuilder tự xếp khối placeholder).
	  * Thêm TRẠM    : thêm một mục vào `Stations`.
	  * Thêm MÓN HÀNG: thêm một mục vào `Shops.<shopId>.Items`.
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

export type JobDef = {
	Name: string,
	ActionText: string,
	BasePay: number,
	HoldDuration: number, -- giây giữ phím
	Skill: string, -- id kỹ năng được cộng XP và tăng lương
	StatDelta: { [string]: number }, -- thay đổi chỉ số sau mỗi lượt làm
	XPReward: number?, -- mặc định JobRules.XPPerShift
	MinEnergy: number?, -- mặc định JobRules.MinEnergyToWork
	Color: Color3?, -- chỉ dùng cho khối placeholder
	Size: Vector3?,
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
}

-- ───────────────────────────── Kỹ năng ─────────────────────────────

local Skills = {
	Order = { "Strength", "Communication" },
	Defs = {
		Strength = { Name = "Sức mạnh" },
		Communication = { Name = "Giao tiếp" },
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
	MinCooldown = 0.5,
	HoldNoticeThrottle = 1.5, -- giây giữa hai thông báo "không làm được" khi bắt đầu giữ phím
}

-- ───────────────────────────── Rate-limit RemoteFunction ─────────────────────────────

local RateLimits = {
	GetState = { Calls = 4, Window = 10 }, -- tối đa 4 lần / 10 giây
	ShopBuy = { Calls = 6, Window = 3 }, -- tối đa 6 lần / 3 giây
}

local Replication = {
	SendRate = 5, -- số snapshot tối đa mỗi giây khi có thay đổi
	InitialStateTimeout = 30, -- giây chờ dữ liệu người chơi cho GetState
}

local Data = {
	StoreName = "EqualSocial_PlayerData_v1",
	KeyPrefix = "u_",
	SchemaVersion = 1,
	AutosaveSeconds = 120,
	LoadRetries = 4,
	LoadRetryDelay = 2,
	SaveRetries = 3,
	SaveRetryDelay = 2,
	ShutdownSaveTimeout = 25, -- BindToClose cho tối đa ~30 giây
}

-- ───────────────────────────── Thông báo & UI ─────────────────────────────

local Notify = {
	Kinds = { "info", "success", "warning", "error", "levelup" },
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

	-- Nghề & kỹ năng
	TooTired = "Bạn quá mệt để làm việc (Năng lượng dưới %d). Hãy nghỉ ngơi trước!",
	JobDone = "%s: +%s · +%d XP %s",
	LevelUp = "Kỹ năng %s đã lên cấp %d!",

	-- Kiệt sức
	Exhausted = "Bạn đã kiệt sức và được đưa đi cấp cứu. Mất %s (%d%% số tiền).",

	-- Cửa hàng (server trả về)
	BoughtConsumable = "Đã mua %s (-%s).",
	BoughtPermanent = "Đã mua %s (-%s). Nổi tiếng +%d!",
	AlreadyOwned = "Bạn đã sở hữu món này rồi.",
	NotEnoughMoney = "Bạn không đủ tiền.",
	TooFarFromShop = "Bạn đang đứng quá xa cửa hàng.",
	InvalidRequest = "Yêu cầu không hợp lệ.",
	TooFast = "Bạn thao tác quá nhanh, hãy chậm lại một chút.",
	NoData = "Dữ liệu của bạn chưa sẵn sàng, vui lòng đợi giây lát.",
	ServerError = "Có lỗi xảy ra, vui lòng thử lại.",

	-- Dữ liệu
	DataLoadFailed = "Không thể tải dữ liệu của bạn. Vui lòng vào lại game sau ít phút.",

	-- HUD (client)
	HudStats = "CHỈ SỐ",
	HudSkills = "KỸ NĂNG",
	HudFame = "Nổi tiếng: %s",
	SkillLevel = "Lv.%d",
	SkillLevelMax = "Lv.%d (Tối đa)",
	SkillXP = "%d/%d XP",

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
}

local Config = {
	Version = "0.1.0",
	GameName = "Equal Social",
	AIName = "AURA",

	-- Tag CollectionService: dịch vụ gắn ProximityPrompt theo tag, nên model thật chỉ cần gắn tag + attribute
	Tags = {
		Job = "ES_Job",
		Station = "ES_Station",
		Shop = "ES_Shop",
	},
	Attributes = {
		Job = "JobId",
		Station = "StationId",
		Shop = "ShopId",
	},

	Data = Data,
	Economy = Economy,
	Reasons = Reasons,
	Stats = Stats,
	Skills = Skills,
	JobRules = JobRules,
	Jobs = Jobs,
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
