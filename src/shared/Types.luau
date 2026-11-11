--!strict
--[[
	Types.luau — các kiểu dùng chung giữa server và client.
	Module này chỉ xuất kiểu; require nó để dùng `Types.PlayerData`, `Types.Snapshot`...
]]

export type SkillRecord = {
	Level: number,
	XP: number,
}

-- Cửa sổ trần tiền kiếm từ quái (xem Config.Combat.HourlyMoneyCap). Lưu theo người chơi để
-- thoát rồi vào lại không làm mới trần.
export type CombatRecord = {
	WindowStart: number, -- thời điểm (giây Unix) bắt đầu cửa sổ hiện tại
	Earned: number, -- số tiền đã kiếm từ quái trong cửa sổ đó
}

-- Một tài sản đang thuê từ AURA (v0.3). `Missed` = số chu kỳ liên tiếp chưa trả được phí duy trì.
export type AssetRecord = {
	LeasedAt: number, -- giây Unix lúc thuê
	Missed: number,
}

-- Tiền đặt giá đang bị khóa. Lưu cùng dữ liệu người chơi: nếu thoát giữa chừng thì lần vào sau
-- được hoàn lại (AuctionService).
export type EscrowRecord = {
	AuctionId: string,
	AssetId: string,
	Amount: number,
}

export type AuraRecord = {
	LastCycle: number, -- chu kỳ AURA cuối cùng đã xử lý phí duy trì / thuế cho người này
	Escrow: EscrowRecord?,
}

-- Dữ liệu lưu vào DataStore (dựng template ở DataService)
export type PlayerData = {
	SchemaVersion: number,
	Money: number,
	Stats: { [string]: number },
	Skills: { [string]: SkillRecord },
	Owned: { [string]: boolean }, -- itemId -> true (đồ sở hữu vĩnh viễn)
	Combat: CombatRecord,
	Assets: { [string]: AssetRecord }, -- assetId -> tài sản đang thuê từ AURA
	Aura: AuraRecord,
}

export type SkillSnapshot = {
	Level: number,
	XP: number,
	Need: number, -- XP cần để lên cấp kế tiếp; 0 nếu đã tối đa
}

-- Ảnh chụp trạng thái server gửi cho client
export type Snapshot = {
	Seq: number, -- tăng dần theo từng người chơi; client bỏ qua snapshot cũ hơn
	Money: number,
	Fame: number,
	NetWorth: number, -- tài sản ròng = tiền + giá các món vĩnh viễn đang sở hữu
	Rank: number?, -- hạng tài sản; nil nếu ngoài top
	Stats: { [string]: number },
	Skills: { [string]: SkillSnapshot },
	Owned: { [string]: boolean },
	Assets: { [string]: number }, -- assetId -> số chu kỳ đang nợ phí duy trì (0 = đúng hạn)
}

export type LeaderboardEntry = {
	Rank: number,
	UserId: number,
	Name: string,
	NetWorth: number,
}

-- Dữ liệu panel bảng xếp hạng (RemoteFunction GetLeaderboard)
export type LeaderboardView = {
	Entries: { LeaderboardEntry },
	UpdatedAt: number, -- giờ server (GetServerTimeNow) lúc làm mới gần nhất
	IsLocal: boolean, -- true: chưa có DataStore xếp hạng, bảng chỉ gồm người chơi trong server
	SelfRank: number?, -- nil nếu ngoài top
	SelfNetWorth: number,
}

-- ── Trạng thái AURA gửi cho mọi client (v0.3) ──
-- Mọi mốc thời gian là giờ server (workspace:GetServerTimeNow()).

export type AuraEvent = {
	Id: string,
	Name: string,
	EndsAt: number,
	Detail: string, -- mô tả hiệu ứng (đã có tên nghề nếu là sự kiện Thiếu lao động)
}

export type AuraLogEntry = {
	Text: string,
	At: number,
}

export type AuctionState = {
	AssetId: string,
	HighestBid: number, -- 0 nếu chưa ai đặt giá
	HighestBidderName: string?,
	StartPrice: number,
	MinNextBid: number,
	EndsAt: number,
}

export type AuraState = {
	Cycle: number,
	CycleEndsAt: number,
	Event: AuraEvent?,
	PriceMultipliers: { [string]: number }, -- nhóm hàng -> hệ số giá đang áp dụng
	JobBonuses: { [string]: number }, -- jobId -> hệ số lương đang áp dụng
	PolicyMultiplier: number, -- hệ số chính sách nhân vào phí duy trì và thuế
	NextTaxAt: number,
	TaxExempt: boolean, -- kỳ thuế kế tiếp được miễn (Ngày không thuế)
	AvgMoney: number,
	OnlinePlayers: number,
	Inflow: number, -- tiền sinh ra trong chu kỳ trước
	Outflow: number, -- tiền bị hút trong chu kỳ trước
	Log: { AuraLogEntry },
	Auction: AuctionState?,
}

-- Trả về cho RemoteFunction GetAuraState: trạng thái chung + phần riêng của người hỏi
export type AuraView = {
	State: AuraState,
	Stock: { [string]: number }, -- tài sản hiếm -> số còn lại (thiếu khoá nếu chưa rõ)
	IsLocalRegistry: boolean, -- true: kho chỉ tính trong server này
	ExpectedTax: number, -- thuế dự kiến của người hỏi ở kỳ tới
	Upkeep: number, -- tổng phí duy trì của người hỏi mỗi chu kỳ (đã nhân hệ số chính sách)
	NetWorth: number,
}

-- Bảng service được truyền cho Init(services)
export type Services = { [string]: any }

return {}
