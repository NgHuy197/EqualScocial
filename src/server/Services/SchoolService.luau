--!strict
--[[
	SchoolService — trường học: học kỹ năng bằng tiền thay vì làm nghề.

	Instance có tag Config.Tags.Class và attribute ClassId (trỏ tới Config.Classes) được gắn prompt.
	Mỗi lần giữ phím xong = một buổi học:
	  * Lớp chỉ mở vào các ngày trong Config.Classes[id].Days (lịch tính từ giờ server, xem Shared/Calendar).
	  * Năng lượng dưới JobRules.MinEnergyToWork => từ chối. Kỹ năng đã tối đa => không thu phí.
	  * Học phí = School.TuitionPerLevel * (level + 1), trừ qua EconomyService (lý do "school").
	  * Cộng XP (cao hơn làm nghề) và áp chi phí chỉ số; KHÔNG có lương.
	Chống exploit: cooldown phía server do Util/Prompts áp dụng; TrySpend là nguyên tử nên không học "chui".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Calendar = require(ReplicatedStorage.Shared.Calendar)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Prompts = require(script.Parent.Parent.Util.Prompts)

type ClassDef = Config.ClassDef

local services: Types.Services = {}

local SchoolService = {}

local function validateConfig()
	for classId, class in Config.Classes do
		if not Config.Skills.Defs[class.Skill] then
			warn(
				`[SchoolService] Lớp '{classId}' dạy kỹ năng không tồn tại: {class.Skill}`
			)
		end
		for statId in class.StatDelta do
			if not Config.Stats.Defs[statId] then
				warn(
					`[SchoolService] Lớp '{classId}' có chi phí cho chỉ số không tồn tại: {statId}`
				)
			end
		end
		for _, weekday in class.Days do
			if weekday < 1 or weekday > Config.Calendar.DaysPerWeek or weekday % 1 ~= 0 then
				warn(
					`[SchoolService] Lớp '{classId}' có ngày mở không hợp lệ: {weekday}`
				)
			end
		end
	end
end

function SchoolService:Init(allServices: Types.Services)
	services = allServices
	validateConfig()
end

function SchoolService:Start()
	Prompts.BindTag(Config.Tags.Class, function(inst: Instance): Prompts.Spec?
		local classId = inst:GetAttribute(Config.Attributes.Class)
		local class = if type(classId) == "string" then Config.Classes[classId] else nil
		if not class then
			warn(
				`[SchoolService] {inst:GetFullName()} có tag Class nhưng attribute {Config.Attributes.Class} không hợp lệ`
			)
			return nil
		end
		return {
			ActionText = class.ActionText,
			ObjectText = `{class.Name} ({Calendar.FormatDays(class.Days)})`,
			HoldDuration = class.HoldDuration,
			OnTriggered = function(player: Player)
				self:_attend(player, class)
			end,
			-- Báo sớm (lớp nghỉ, thiếu tiền, quá mệt...) để không phải giữ phím vô ích
			OnHoldBegan = function(player: Player)
				local ok, reason = self:_canAttend(player, class)
				if not ok and reason then
					services.Replication:Notify(player, reason, "warning")
				end
			end,
		}
	end)
end

-- Học phí buổi tới của người chơi cho kỹ năng này
function SchoolService:GetTuition(player: Player, skillId: string): number
	return Config.School.TuitionPerLevel * (services.Skills:GetLevel(player, skillId) + 1)
end

-- Có học được buổi này lúc này không? Trả về (được, lý do nếu không)
function SchoolService:_canAttend(player: Player, class: ClassDef): (boolean, string?)
	local energy = services.Stats:Get(player, "Energy")
	if not energy then
		return false, Config.Text.NoData
	end

	if not Calendar.IsOpen(class.Days, Workspace:GetServerTimeNow()) then
		return false,
			string.format(Config.Text.ClassClosed, class.Name, Calendar.FormatDays(class.Days))
	end

	local skillDef = Config.Skills.Defs[class.Skill]
	local skillName = if skillDef then skillDef.Name else class.Skill
	if services.Skills:GetLevel(player, class.Skill) >= Config.Skills.MaxLevel then
		return false, string.format(Config.Text.ClassSkillMaxed, skillName)
	end

	if energy < Config.JobRules.MinEnergyToWork then
		return false, string.format(Config.Text.TooTired, Config.JobRules.MinEnergyToWork)
	end

	local tuition = self:GetTuition(player, class.Skill)
	if services.Economy:Get(player) < tuition then
		return false, string.format(Config.Text.ClassNoMoney, Format.money(tuition))
	end
	return true, nil
end

function SchoolService:_attend(player: Player, class: ClassDef)
	local ok, reason = self:_canAttend(player, class)
	if not ok then
		if reason then
			services.Replication:Notify(player, reason, "warning")
		end
		return
	end

	-- Học phí tính theo level TRƯỚC khi cộng XP của buổi này. TrySpend nguyên tử: không đủ thì dừng.
	local tuition = self:GetTuition(player, class.Skill)
	if not services.Economy:TrySpend(player, tuition, Config.Reasons.School) then
		services.Replication:Notify(
			player,
			string.format(Config.Text.ClassNoMoney, Format.money(tuition)),
			"warning"
		)
		return
	end

	local xp = class.XPReward or Config.School.XPPerLesson
	services.Stats:Modify(player, class.StatDelta)
	services.Skills:AddXP(player, class.Skill, xp)

	local skillDef = Config.Skills.Defs[class.Skill]
	services.Replication:Notify(
		player,
		string.format(
			Config.Text.ClassDone,
			class.Name,
			Format.money(tuition),
			math.floor(xp),
			if skillDef then skillDef.Name else class.Skill
		),
		"success"
	)
end

return SchoolService
