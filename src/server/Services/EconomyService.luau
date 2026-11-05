--!strict
--[[
	EconomyService — NƠI DUY NHẤT được phép thay đổi tiền của người chơi.

	  Add(player, amount, reason)           -> số tiền thực sự cộng (0 nếu thất bại)
	  TrySpend(player, amount, reason)      -> true nếu đủ tiền và đã trừ
	  TakePercent(player, percent, reason)  -> số tiền thực sự bị lấy (percent trong (0, 1])
	  Get(player)                           -> số dư hiện tại

	Mọi hàm bắt buộc có `reason` (xem Config.Reasons) để sau này AURA đánh thuế, ghi log, chống lạm phát.
	Đăng ký OnTransaction(callback) để lắng nghe mọi giao dịch (AURA v0.3 sẽ dùng chỗ này).

	QUY TẮC: service khác KHÔNG ĐƯỢC tự sửa data.Money. Chỉ gọi các hàm ở đây.
	Mọi hàm đều đồng bộ (không yield) nên kiểm tra-rồi-trừ là nguyên tử, không thể mua đúp.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(script.Parent.Parent.Util.Validate)

export type Transaction = {
	Player: Player,
	Delta: number, -- dương: nhận, âm: mất
	Reason: string,
	Balance: number, -- số dư sau giao dịch
}

local services: Types.Services = {}
local listeners: { (transaction: Transaction) -> () } = {}

local EconomyService = {}

function EconomyService:Init(allServices: Types.Services)
	services = allServices
end

function EconomyService:Start() end

function EconomyService:Get(player: Player): number
	local data = services.Data:Get(player)
	return if data then data.Money else 0
end

-- Lắng nghe mọi giao dịch đã hoàn tất
function EconomyService:OnTransaction(callback: (transaction: Transaction) -> ())
	table.insert(listeners, callback)
end

local function record(player: Player, delta: number, reason: string, balance: number)
	if Config.Economy.LogTransactions then
		local sign = if delta >= 0 then "+" else ""
		print(`[Economy] {player.Name} {sign}{delta} ({reason}) -> {balance}`)
	end
	services.Replication:MarkDirty(player)
	local transaction: Transaction = {
		Player = player,
		Delta = delta,
		Reason = reason,
		Balance = balance,
	}
	for _, callback in listeners do
		task.spawn(callback, transaction)
	end
end

function EconomyService:Add(player: Player, amount: number, reason: string): number
	if type(reason) ~= "string" or not Validate.isFiniteNumber(amount) or amount <= 0 then
		return 0
	end
	local data = services.Data:Get(player)
	if not data then
		return 0
	end
	local applied = math.min(math.floor(amount), Config.Economy.MaxMoney - data.Money)
	if applied <= 0 then
		return 0
	end
	data.Money += applied
	record(player, applied, reason, data.Money)
	return applied
end

function EconomyService:TrySpend(player: Player, amount: number, reason: string): boolean
	if type(reason) ~= "string" or not Validate.isFiniteNumber(amount) or amount < 0 then
		return false
	end
	local data = services.Data:Get(player)
	if not data then
		return false
	end
	local cost = math.floor(amount)
	if cost > data.Money then
		return false
	end
	if cost == 0 then
		return true
	end
	data.Money -= cost
	record(player, -cost, reason, data.Money)
	return true
end

function EconomyService:TakePercent(player: Player, percent: number, reason: string): number
	if type(reason) ~= "string" or not Validate.isFiniteNumber(percent) or percent <= 0 then
		return 0
	end
	local data = services.Data:Get(player)
	if not data then
		return 0
	end
	local taken = math.floor(data.Money * math.min(percent, 1))
	if taken <= 0 then
		return 0
	end
	data.Money -= taken
	record(player, -taken, reason, data.Money)
	return taken
end

return EconomyService
