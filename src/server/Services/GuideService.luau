--!strict
--[[
	GuideService — nhiệm vụ hướng dẫn cho người mới (v0.6).

	Một chuỗi bước cố định trong Config.Guide.Steps dẫn người chơi qua vòng lặp chính: làm nghề, ăn,
	nghỉ ở trạm, học, đánh quái, ghé Trụ sở AURA. Làm đúng bước đang hiện thì sang bước kế; HUD hiện
	bước đang làm (qua snapshot). KHÔNG có phần thưởng: mọi người vẫn xuất phát như nhau.

	  * Tiến độ lưu trong data.Guide.Step (1..#Steps; lớn hơn #Steps = đã xong), giữ qua các mùa.
	  * Bước gắn với lý do giao dịch (Config.Guide.ReasonEvents) được nhận qua EconomyService.OnTransaction;
	    bước không có giao dịch (dùng trạm, mở Trụ sở AURA) do service tương ứng gọi Report.
	  * Chỉ server ghi tiến độ; client không có Remote nào để tự hoàn thành bước.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local services: Types.Services = {}

local GuideService = {}

function GuideService:Init(allServices: Types.Services)
	services = allServices
end

function GuideService:Start()
	services.Economy:OnTransaction(function(transaction)
		local event = Config.Guide.ReasonEvents[transaction.Reason]
		if event then
			self:Report(transaction.Player, event)
		end
	end)
end

-- Bước đang làm (nil nếu đã xong hướng dẫn hoặc chưa có dữ liệu)
function GuideService:GetStep(player: Player): (Config.GuideStep?, number)
	local data = services.Data:Get(player)
	if not data then
		return nil, 0
	end
	local index = data.Guide.Step
	return Config.Guide.Steps[index], index
end

-- Dòng hiện trên HUD: "(2/6) Mua một món ăn ở Quán ăn"; nil nếu đã xong
function GuideService:GetText(player: Player): string?
	local step, index = self:GetStep(player)
	if not step then
		return nil
	end
	return string.format(Config.Text.GuideProgress, index, #Config.Guide.Steps, step.Text)
end

-- Báo một việc người chơi vừa làm. Chỉ tính khi đúng là bước đang hiện.
function GuideService:Report(player: Player, event: string)
	local data = services.Data:Get(player)
	if not data then
		return
	end
	local step = Config.Guide.Steps[data.Guide.Step]
	if not step or step.Event ~= event then
		return
	end
	data.Guide.Step += 1
	services.Replication:MarkDirty(player)

	local nextStep = Config.Guide.Steps[data.Guide.Step]
	if nextStep then
		services.Replication:Notify(
			player,
			string.format(Config.Text.GuideStepDone, nextStep.Text),
			"success"
		)
	else
		services.Replication:Notify(player, Config.Text.GuideFinished, "levelup")
	end
end

return GuideService
