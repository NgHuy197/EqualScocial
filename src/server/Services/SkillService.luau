--!strict
--[[
	SkillService — kỹ năng (Sức mạnh, Giao tiếp...) và XP.

	  * XP cần để lên cấp kế tiếp = XPBase + XPPerLevel * levelHiệnTại, tối đa MaxLevel.
	  * Level ảnh hưởng lương nghề: lương = lươngGốc * (1 + PayBonusPerLevel * level).
	  * Chỉ server cộng XP (AddXP); client không có đường nào để tự tăng.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local services: Types.Services = {}

local SkillService = {}

function SkillService:Init(allServices: Types.Services)
	services = allServices
end

function SkillService:Start() end

-- XP cần để đi từ `level` lên `level + 1`
function SkillService:XPNeeded(level: number): number
	return Config.Skills.XPBase + Config.Skills.XPPerLevel * level
end

function SkillService:GetLevel(player: Player, skillId: string): number
	local data = services.Data:Get(player)
	local record = if data then data.Skills[skillId] else nil
	return if record then record.Level else Config.Skills.StartLevel
end

-- Hệ số nhân lương theo level kỹ năng (level 0 => x1.0, level 20 => x3.0)
function SkillService:GetPayMultiplier(player: Player, skillId: string): number
	return 1 + Config.Skills.PayBonusPerLevel * self:GetLevel(player, skillId)
end

-- Cộng XP, tự xử lý lên cấp (có thể lên nhiều cấp). Trả về số cấp vừa lên.
function SkillService:AddXP(player: Player, skillId: string, amount: number): number
	local def = Config.Skills.Defs[skillId]
	local data = services.Data:Get(player)
	if not def or not data or amount <= 0 then
		return 0
	end
	local record = data.Skills[skillId]
	if not record or record.Level >= Config.Skills.MaxLevel then
		return 0
	end

	record.XP += amount
	local gained = 0
	while record.Level < Config.Skills.MaxLevel do
		local need = self:XPNeeded(record.Level)
		if record.XP < need then
			break
		end
		record.XP -= need
		record.Level += 1
		gained += 1
		services.Replication:Notify(
			player,
			string.format(Config.Text.LevelUp, def.Name, record.Level),
			"levelup"
		)
	end
	if record.Level >= Config.Skills.MaxLevel then
		record.XP = 0 -- đã tối đa: không tích XP thừa
	end

	services.Replication:MarkDirty(player)
	return gained
end

return SkillService
