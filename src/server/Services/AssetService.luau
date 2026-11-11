--!strict
--[[
	AssetService — tài sản (nhà, xe) là QUYỀN THUÊ từ AURA, không bao giờ thuộc về người chơi.

	  * Thuê tài sản thường qua Lease: trả giá thuê một lần (không hoàn) + phí duy trì mỗi chu kỳ AURA.
	  * Tài sản hiếm (Config.Assets[id].Stock) không thuê trực tiếp được, chỉ qua đấu giá (GrantRare).
	    Kho toàn cầu do Util/AssetRegistry quản lý (nhận bằng UpdateAsync, không cấp trùng giữa server).
	  * ProcessCycle (AuraService gọi mỗi chu kỳ): tự trừ phí duy trì qua EconomyService (lý do "maintenance").
	    Không đủ tiền => ghi nợ một chu kỳ và cảnh báo; nợ quá GraceCycles chu kỳ => THU HỒI (rare về kho).
	    Lần trả kế tiếp trả bù mọi chu kỳ đã nợ.
	  * Tài sản đang thuê cộng vào Nổi tiếng và tài sản ròng (theo giá thuê); mất khi bị thu hồi / trả lại.

	Mọi thay đổi tiền đều đi qua EconomyService; handler Remote validate id, rate-limit, bọc pcall.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local AssetRegistry = require(script.Parent.Parent.Util.AssetRegistry)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validate = require(script.Parent.Parent.Util.Validate)

type PlayerData = Types.PlayerData

local AssetLease = Remotes.Function("AssetLease")
local AssetReturn = Remotes.Function("AssetReturn")

local services: Types.Services = {}
local registry = AssetRegistry.new()
local leaseLimiter =
	RateLimiter.new(Config.RateLimits.AssetLease.Calls, Config.RateLimits.AssetLease.Window)
local returnLimiter =
	RateLimiter.new(Config.RateLimits.AssetReturn.Calls, Config.RateLimits.AssetReturn.Window)

local AssetService = {}

local function sortedAssetIds(data: PlayerData): { string }
	local ids: { string } = {}
	for assetId in data.Assets do
		table.insert(ids, assetId)
	end
	table.sort(ids)
	return ids
end

function AssetService:Init(allServices: Types.Services)
	services = allServices
	registry:Init()
	for assetId, def in Config.Assets do
		if not Validate.isId(assetId) then
			warn(`[AssetService] Id tài sản không hợp lệ: {assetId}`)
		end
		if def.Stock ~= nil and def.Stock < 1 then
			warn(`[AssetService] Tài sản hiếm '{assetId}' có Stock < 1`)
		end
	end
end

function AssetService:Start()
	AssetLease.OnServerInvoke = function(player: Player, assetId: any)
		return self:_handle(player, assetId, leaseLimiter, function(id: string)
			return self:Lease(player, id)
		end)
	end
	AssetReturn.OnServerInvoke = function(player: Player, assetId: any)
		return self:_handle(player, assetId, returnLimiter, function(id: string)
			return self:Return(player, id)
		end)
	end

	-- Vào game: gửi nhịp cho từng tài sản hiếm; suất đã bị người khác nhận vì vắng mặt lâu => thu hồi
	services.Data:OnLoaded(function(player: Player)
		self:VerifyRare(player)
	end)
end

-- Gửi nhịp lên registry cho mọi tài sản hiếm người chơi đang giữ (có thể yield). Thu hồi những tài
-- sản mà registry báo đã bị gỡ (chủ vắng mặt quá Config.AssetRegistry.IdleSeconds và có người nhận).
-- Registry lỗi thì giữ nguyên, không thu hồi nhầm.
function AssetService:VerifyRare(player: Player)
	local data = services.Data:Get(player)
	if not data then
		return
	end
	for _, assetId in sortedAssetIds(data) do
		local def = Config.Assets[assetId]
		if def and def.Stock ~= nil then
			local result = registry:Touch(assetId, player.UserId)
			-- Sau khi yield: người chơi có thể đã rời game hoặc đã trả tài sản
			local current = services.Data:Get(player)
			if result == "evicted" and current and current.Assets[assetId] then
				current.Assets[assetId] = nil
				services.Replication:Notify(
					player,
					string.format(
						Config.Text.AssetIdleRevoked,
						def.Name,
						math.floor(Config.AssetRegistry.IdleSeconds / 86400)
					),
					"error"
				)
				services.Replication:MarkDirty(player)
			end
		end
	end
end

-- ───────────────────────────── API công khai ─────────────────────────────

-- Tổng Nổi tiếng của các tài sản đang thuê
function AssetService:GetFame(player: Player): number
	local data = services.Data:Get(player)
	if not data then
		return 0
	end
	local fame = 0
	for assetId in data.Assets do
		local def = Config.Assets[assetId]
		if def then
			fame += def.Fame
		end
	end
	return fame
end

-- Tổng giá thuê của các tài sản đang thuê (tính vào tài sản ròng)
function AssetService:GetValue(player: Player): number
	local data = services.Data:Get(player)
	if not data then
		return 0
	end
	local value = 0
	for assetId in data.Assets do
		local def = Config.Assets[assetId]
		if def then
			value += def.Price
		end
	end
	return value
end

-- Phí duy trì một tài sản mỗi chu kỳ, đã nhân hệ số chính sách của AURA
function AssetService:GetFee(assetId: string): number
	local def = Config.Assets[assetId]
	if not def then
		return 0
	end
	return math.floor(def.FeePerCycle * services.Aura:GetPolicyMultiplier() + 0.5)
end

-- Tổng phí duy trì mỗi chu kỳ của người chơi (chưa tính nợ cũ)
function AssetService:GetUpkeep(player: Player): number
	local data = services.Data:Get(player)
	if not data then
		return 0
	end
	local total = 0
	for assetId in data.Assets do
		total += self:GetFee(assetId)
	end
	return total
end

-- Số tài sản hiếm còn lại trong kho; nil nếu không biết. Có thể yield (đọc DataStore, có đệm).
function AssetService:GetRemaining(assetId: string): number?
	return registry:Remaining(assetId)
end

function AssetService:IsLocalRegistry(): boolean
	return registry:IsLocal()
end

-- Thuê trực tiếp một tài sản thường. Trả về (thành công, thông báo). Không yield.
function AssetService:Lease(player: Player, assetId: string): (boolean, string)
	local def = Config.Assets[assetId]
	local data = services.Data:Get(player)
	if not def then
		return false, Config.Text.InvalidRequest
	end
	if not data then
		return false, Config.Text.NoData
	end
	if def.Stock ~= nil then
		return false, Config.Text.AssetRareOnly
	end
	if data.Assets[assetId] then
		return false, Config.Text.AssetAlreadyLeased
	end
	-- Kiểm tra và ghi nằm trong cùng một bước không yield nên không thể thuê đúp
	if not services.Economy:TrySpend(player, def.Price, Config.Reasons.AssetLease) then
		return false, Config.Text.NotEnoughMoney
	end
	data.Assets[assetId] = { LeasedAt = os.time(), Missed = 0 }
	services.Replication:MarkDirty(player)
	return true,
		string.format(
			Config.Text.AssetLeased,
			def.Name,
			Format.money(def.Price),
			def.Fame,
			Format.money(self:GetFee(assetId))
		)
end

-- Cấp tài sản hiếm cho người thắng đấu giá: nhận từ registry (yield) rồi ghi vào dữ liệu.
-- Tiền đặt giá đã được AuctionService khóa trước đó. Trả về (thành công, lý do).
function AssetService:GrantRare(player: Player, assetId: string): (boolean, string?)
	local def = Config.Assets[assetId]
	if not def or def.Stock == nil then
		return false, "unavailable"
	end
	local ok, reason = registry:TryClaim(assetId, player.UserId)
	if not ok then
		return false, reason
	end
	-- Trong lúc chờ DataStore người chơi có thể đã thoát: trả lại kho, không cấp
	local data = services.Data:Get(player)
	if not data then
		registry:Release(assetId, player.UserId)
		return false, "unavailable"
	end
	data.Assets[assetId] = { LeasedAt = os.time(), Missed = 0 }
	services.Replication:MarkDirty(player)
	return true, nil
end

-- Trả lại tài sản cho AURA (không hoàn tiền nếu ReturnRefundPercent = 0). Có thể yield nếu là tài sản hiếm.
function AssetService:Return(player: Player, assetId: string): (boolean, string)
	local def = Config.Assets[assetId]
	local data = services.Data:Get(player)
	if not def then
		return false, Config.Text.InvalidRequest
	end
	if not data then
		return false, Config.Text.NoData
	end
	if not data.Assets[assetId] then
		return false, Config.Text.AssetNotLeased
	end
	data.Assets[assetId] = nil
	services.Replication:MarkDirty(player)

	local refund = math.floor(def.Price * Config.Aura.ReturnRefundPercent / 100)
	if refund > 0 then
		services.Economy:Add(player, refund, Config.Reasons.AssetRefund)
	end
	if def.Stock ~= nil then
		registry:Release(assetId, player.UserId) -- yield: đã ghi dữ liệu xong nên an toàn
	end
	if refund > 0 then
		return true, string.format(Config.Text.AssetReturnedRefund, def.Name, Format.money(refund))
	end
	return true, string.format(Config.Text.AssetReturned, def.Name)
end

-- Xử lý một chu kỳ AURA cho người chơi: trừ phí duy trì, ghi nợ, thu hồi nếu quá ân hạn.
function AssetService:ProcessCycle(player: Player, data: PlayerData)
	local totalPaid = 0
	for _, assetId in sortedAssetIds(data) do
		local def = Config.Assets[assetId]
		local record = data.Assets[assetId]
		if not def then
			data.Assets[assetId] = nil -- tài sản đã bị xoá khỏi Config
		else
			local fee: number = self:GetFee(assetId)
			-- Trả bù cả những chu kỳ đã nợ
			local owed = fee * (record.Missed + 1)
			if services.Economy:TrySpend(player, owed, Config.Reasons.Maintenance) then
				totalPaid += owed
				record.Missed = 0
			else
				record.Missed += 1
				if record.Missed > Config.Aura.GraceCycles then
					self:_revoke(player, data, assetId, def)
				else
					services.Replication:Notify(
						player,
						string.format(
							Config.Text.MaintenanceLate,
							Format.money(owed + fee),
							def.Name,
							Config.Aura.GraceCycles - record.Missed + 1
						),
						"aura"
					)
				end
			end
		end
	end
	if totalPaid > 0 then
		services.Replication:Notify(
			player,
			string.format(Config.Text.MaintenancePaid, Format.money(totalPaid)),
			"aura"
		)
	end
	services.Replication:MarkDirty(player)
	-- Nhịp cho tài sản hiếm mỗi chu kỳ (luồng riêng vì gọi DataStore)
	task.spawn(function()
		self:VerifyRare(player)
	end)
end

-- ───────────────────────────── Nội bộ ─────────────────────────────

function AssetService:_revoke(
	player: Player,
	data: PlayerData,
	assetId: string,
	def: Config.AssetDef
)
	data.Assets[assetId] = nil
	if def.Stock ~= nil then
		task.spawn(function()
			registry:Release(assetId, player.UserId)
		end)
	end
	services.Replication:Notify(
		player,
		string.format(Config.Text.AssetRevoked, def.Name, Config.Aura.GraceCycles),
		"error"
	)
end

-- Khung chung cho handler Remote: validate, rate-limit, pcall
function AssetService:_handle(
	player: Player,
	assetId: any,
	limiter: RateLimiter.RateLimiter,
	action: (assetId: string) -> (boolean, string)
): (boolean, string)
	if not Validate.isPlayer(player) then
		return false, Config.Text.InvalidRequest
	end
	if not limiter:Allow(player) then
		return false, Config.Text.TooFast
	end
	if not Validate.isId(assetId) then
		return false, Config.Text.InvalidRequest
	end
	if not services.Aura:IsNearHq(player) then
		return false, Config.Text.TooFarFromAura
	end
	local ok, success, message = pcall(action, assetId :: string)
	if not ok then
		warn(`[AssetService] Lỗi xử lý tài sản: {tostring(success)}`)
		return false, Config.Text.ServerError
	end
	return success, message
end

return AssetService
