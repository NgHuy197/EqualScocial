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

-- Dữ liệu lưu vào DataStore (dựng template ở DataService)
export type PlayerData = {
	SchemaVersion: number,
	Money: number,
	Stats: { [string]: number },
	Skills: { [string]: SkillRecord },
	Owned: { [string]: boolean }, -- itemId -> true (đồ sở hữu vĩnh viễn)
	Combat: CombatRecord,
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

-- Bảng service được truyền cho Init(services)
export type Services = { [string]: any }

return {}
