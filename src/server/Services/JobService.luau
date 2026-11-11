--!strict
--[[
	JobService — làm nghề kiếm tiền qua ProximityPrompt (giữ phím).

	Instance có tag Config.Tags.Job và attribute JobId (trỏ tới Config.Jobs) sẽ được gắn prompt tự động.
	Mỗi lần giữ phím xong = một lượt làm:
	  * Năng lượng dưới MinEnergy => từ chối.
	  * Lương = BasePay * (1 + PayBonusPerLevel * level kỹ năng) — tiền cộng qua EconomyService.
	  * Trừ/cộng chỉ số theo job.StatDelta, cộng XP kỹ năng.
	Chống exploit: cooldown phía server do Util/Prompts áp dụng (≈ HoldDuration * CooldownFactor).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Describe = require(script.Parent.Parent.Util.Describe)
local Prompts = require(script.Parent.Parent.Util.Prompts)

type JobDef = Config.JobDef

local services: Types.Services = {}

local JobService = {}

-- Phát hiện sớm lỗi cấu hình (gõ sai id kỹ năng / chỉ số) thay vì để lỗi xuất hiện lúc đang chơi
local function validateConfig()
	for jobId, job in Config.Jobs do
		if not Config.Skills.Defs[job.Skill] then
			warn(`[JobService] Job '{jobId}' dùng kỹ năng không tồn tại: {job.Skill}`)
		end
		for statId in job.StatDelta do
			if not Config.Stats.Defs[statId] then
				warn(
					`[JobService] Job '{jobId}' có StatDelta cho chỉ số không tồn tại: {statId}`
				)
			end
		end
		local requires: { Config.Requirement } = job.Requires or {}
		for _, requirement in requires do
			if not Config.Skills.Defs[requirement.Skill] then
				warn(
					`[JobService] Job '{jobId}' yêu cầu kỹ năng không tồn tại: {requirement.Skill}`
				)
			end
		end
	end
end

function JobService:Init(allServices: Types.Services)
	services = allServices
	validateConfig()
end

function JobService:Start()
	Prompts.BindTag(Config.Tags.Job, function(inst: Instance): Prompts.Spec?
		local jobId = inst:GetAttribute(Config.Attributes.Job)
		local job = if type(jobId) == "string" then Config.Jobs[jobId] else nil
		if not job then
			warn(
				`[JobService] {inst:GetFullName()} có tag Job nhưng attribute {Config.Attributes.Job} không hợp lệ`
			)
			return nil
		end
		return {
			ActionText = job.ActionText,
			ObjectText = Describe.JobTitle(job), -- nghề có điều kiện hiện kèm "(cần ...)"
			HoldDuration = job.HoldDuration,
			OnTriggered = function(player: Player)
				self:_work(player, job, jobId)
			end,
			-- Báo sớm nếu quá mệt, đỡ phải giữ phím cả vài giây rồi mới biết
			OnHoldBegan = function(player: Player)
				local canWork, reason = self:_canWork(player, job)
				if not canWork and reason then
					services.Replication:Notify(player, reason, "warning")
				end
			end,
		}
	end)
end

-- Có được làm nghề này lúc này không? Trả về (được, lý do nếu không)
function JobService:_canWork(player: Player, job: JobDef): (boolean, string?)
	local energy = services.Stats:Get(player, "Energy")
	if not energy then
		return false, Config.Text.NoData
	end
	local minEnergy = job.MinEnergy or Config.JobRules.MinEnergyToWork
	if energy < minEnergy then
		return false, string.format(Config.Text.TooTired, minEnergy)
	end

	-- Điều kiện mở khóa: liệt kê các kỹ năng chưa đủ level (kèm level hiện tại)
	local missing: { string } = {}
	local requires: { Config.Requirement } = job.Requires or {}
	for _, requirement in requires do
		local level = services.Skills:GetLevel(player, requirement.Skill)
		if level < requirement.Level then
			local def = Config.Skills.Defs[requirement.Skill]
			table.insert(
				missing,
				string.format(
					Config.Text.RequirementProgress,
					if def then def.Name else requirement.Skill,
					requirement.Level,
					level
				)
			)
		end
	end
	if #missing > 0 then
		return false, string.format(Config.Text.JobLocked, table.concat(missing, ", "))
	end
	return true, nil
end

-- jobId (tuỳ chọn) dùng cho sự kiện của AURA: hệ số lương nghề thiếu người và ghi nhận số người đang làm
function JobService:_work(player: Player, job: JobDef, jobId: string?)
	local canWork, reason = self:_canWork(player, job)
	if not canWork then
		if reason then
			services.Replication:Notify(player, reason, "warning")
		end
		return
	end

	-- Lương tính theo level TRƯỚC khi cộng XP của lượt này
	local multiplier = services.Skills:GetPayMultiplier(player, job.Skill)
	local eventBonus = if jobId then services.Aura:GetPayMultiplier(jobId) else 1
	local pay = math.floor(job.BasePay * multiplier * eventBonus + 0.5)
	local xp = job.XPReward or Config.JobRules.XPPerShift

	local paid = services.Economy:Add(player, pay, Config.Reasons.Job)
	if jobId then
		services.Aura:NoteWork(player, jobId)
	end
	services.Stats:Modify(player, job.StatDelta)
	services.Skills:AddXP(player, job.Skill, xp)

	local skillDef = Config.Skills.Defs[job.Skill]
	services.Replication:Notify(
		player,
		string.format(
			Config.Text.JobDone,
			job.Name,
			Format.money(paid),
			math.floor(xp),
			if skillDef then skillDef.Name else job.Skill
		),
		"success"
	)
end

return JobService
