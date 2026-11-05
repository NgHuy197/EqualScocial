--!strict
--[[
	Types.luau — các kiểu dùng chung giữa server và client.
	Module này chỉ xuất kiểu; require nó để dùng `Types.PlayerData`, `Types.Snapshot`...
]]

export type SkillRecord = {
	Level: number,
	XP: number,
}

-- Dữ liệu lưu vào DataStore (dựng template ở DataService)
export type PlayerData = {
	SchemaVersion: number,
	Money: number,
	Stats: { [string]: number },
	Skills: { [string]: SkillRecord },
	Owned: { [string]: boolean }, -- itemId -> true (đồ sở hữu vĩnh viễn)
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
	Stats: { [string]: number },
	Skills: { [string]: SkillSnapshot },
	Owned: { [string]: boolean },
}

-- Bảng service được truyền cho Init(services)
export type Services = { [string]: any }

return {}
