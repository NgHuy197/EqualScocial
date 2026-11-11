--!strict
--[[
	Describe.luau — tạo chuỗi mô tả (tiếng Việt) từ Config, dùng chung cho service và WorldBuilder
	để câu chữ ở nhãn trên map, ProximityPrompt và thông báo luôn khớp nhau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

type JobDef = Config.JobDef

local Describe = {}

-- "Khéo tay Lv.3" hoặc "Trí tuệ Lv.5, Giao tiếp Lv.3"; chuỗi rỗng nếu nghề không có điều kiện
function Describe.Requirements(job: JobDef): string
	local requires = job.Requires
	if not requires or #requires == 0 then
		return ""
	end
	local parts: { string } = {}
	for _, requirement in requires do
		local def = Config.Skills.Defs[requirement.Skill]
		table.insert(
			parts,
			string.format(
				Config.Text.RequirementItem,
				if def then def.Name else requirement.Skill,
				requirement.Level
			)
		)
	end
	return table.concat(parts, ", ")
end

-- "Kỹ thuật viên (cần Khéo tay Lv.3)" hoặc chỉ tên nghề nếu không có điều kiện
function Describe.JobTitle(job: JobDef): string
	local requirements = Describe.Requirements(job)
	if requirements == "" then
		return job.Name
	end
	return string.format(Config.Text.JobTitleLocked, job.Name, requirements)
end

return Describe
