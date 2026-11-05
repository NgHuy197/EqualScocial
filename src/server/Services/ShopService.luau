--!strict
--[[
	ShopService — cửa hàng (Quán ăn, Cửa hàng thời trang...).

	  * Instance có tag Config.Tags.Shop + attribute ShopId: ProximityPrompt (nhấn E) -> server gửi
	    OpenShop(shopId) cho đúng người chơi đó để client mở cửa sổ.
	  * Mua qua RemoteFunction ShopBuy(shopId, itemId) -> (ok, message). Server kiểm tra:
	      1. rate-limit,  2. kiểu dữ liệu/độ dài id,  3. shop & item có trong Config,
	      4. người chơi còn sống và đứng cách cửa hàng <= ShopRules.MaxBuyDistance studs,
	      5. đồ vĩnh viễn: không mua trùng,  6. đủ tiền (EconomyService.TrySpend).
	  * consumable: dùng ngay, cộng chỉ số.  permanent: sở hữu vĩnh viễn, cộng Nổi tiếng.
	  * Nổi tiếng KHÔNG được lưu: luôn tính ra từ danh sách đồ đang sở hữu (GetFame).

	Handler không yield giữa lúc kiểm tra "đã sở hữu?" và lúc ghi sở hữu, nên không thể mua đúp
	bằng cách gọi nhiều request cùng lúc.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Prompts = require(script.Parent.Parent.Util.Prompts)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validate = require(script.Parent.Parent.Util.Validate)

type ItemDef = Config.ItemDef

local OpenShop = Remotes.Event("OpenShop")
local ShopBuy = Remotes.Function("ShopBuy")

local services: Types.Services = {}
local buyLimiter =
	RateLimiter.new(Config.RateLimits.ShopBuy.Calls, Config.RateLimits.ShopBuy.Window)
-- Chỉ mục tra cứu nhanh, dựng từ Config lúc Init
local itemsByShop: { [string]: { [string]: ItemDef } } = {}
local itemById: { [string]: ItemDef } = {}

local ShopService = {}

function ShopService:Init(allServices: Types.Services)
	services = allServices

	for shopId, shop in Config.Shops do
		if not Validate.isId(shopId) then
			warn(`[ShopService] Id cửa hàng không hợp lệ: {shopId}`)
		end
		local items: { [string]: ItemDef } = {}
		for _, item in shop.Items do
			if not Validate.isId(item.Id) then
				warn(`[ShopService] Id món hàng không hợp lệ: {item.Id}`)
			elseif itemById[item.Id] then
				warn(`[ShopService] Id món hàng bị trùng giữa các cửa hàng: {item.Id}`)
			end
			if item.Kind == "consumable" and item.Effects then
				for statId in item.Effects do
					if not Config.Stats.Defs[statId] then
						warn(
							`[ShopService] Món '{item.Id}' có hiệu ứng cho chỉ số không tồn tại: {statId}`
						)
					end
				end
			end
			items[item.Id] = item
			itemById[item.Id] = item
		end
		itemsByShop[shopId] = items
	end
end

function ShopService:Start()
	Prompts.BindTag(Config.Tags.Shop, function(inst: Instance): Prompts.Spec?
		local shopId = inst:GetAttribute(Config.Attributes.Shop)
		local shop = if type(shopId) == "string" then Config.Shops[shopId] else nil
		if not shop or type(shopId) ~= "string" then
			warn(
				`[ShopService] {inst:GetFullName()} có tag Shop nhưng attribute {Config.Attributes.Shop} không hợp lệ`
			)
			return nil
		end
		return {
			ActionText = shop.ActionText,
			ObjectText = shop.Name,
			HoldDuration = 0,
			Cooldown = Config.ShopRules.OpenCooldown,
			OnTriggered = function(player: Player)
				OpenShop:FireClient(player, shopId)
			end,
		}
	end)

	ShopBuy.OnServerInvoke = function(player: Player, shopId: any, itemId: any)
		local ok, success, message = pcall(function()
			return self:_handleBuy(player, shopId, itemId)
		end)
		if not ok then
			warn(`[ShopService] Lỗi khi xử lý mua hàng: {tostring(success)}`)
			return false, Config.Text.ServerError
		end
		return success, message
	end
end

-- ───────────────────────────── API công khai ─────────────────────────────

-- Nổi tiếng = tổng Fame của các món vĩnh viễn đang sở hữu
function ShopService:GetFame(player: Player): number
	local data = services.Data:Get(player)
	if not data then
		return 0
	end
	local fame = 0
	for itemId in data.Owned do
		local item = itemById[itemId]
		if item and item.Fame then
			fame += item.Fame
		end
	end
	return fame
end

-- ───────────────────────────── Nội bộ ─────────────────────────────

-- Người chơi có đang đứng trong ShopRules.MaxBuyDistance của ít nhất một cửa hàng mang ShopId này?
local function isNearShop(player: Player, shopId: string): boolean
	for _, inst in CollectionService:GetTagged(Config.Tags.Shop) do
		if
			inst:IsDescendantOf(Workspace)
			and inst:GetAttribute(Config.Attributes.Shop) == shopId
		then
			local anchor = Prompts.GetAnchor(inst)
			if
				anchor
				and Validate.isWithin(player, anchor.Position, Config.ShopRules.MaxBuyDistance)
			then
				return true
			end
		end
	end
	return false
end

-- Dữ liệu `shopId` / `itemId` đến từ client nên là `any` và phải được validate kỹ
function ShopService:_handleBuy(player: Player, shopId: any, itemId: any): (boolean, string)
	if not Validate.isPlayer(player) then
		return false, Config.Text.InvalidRequest
	end
	if not buyLimiter:Allow(player) then
		return false, Config.Text.TooFast
	end
	if not Validate.isId(shopId) or not Validate.isId(itemId) then
		return false, Config.Text.InvalidRequest
	end
	return self:_buy(player, shopId :: string, itemId :: string)
end

function ShopService:_buy(player: Player, shopId: string, itemId: string): (boolean, string)
	local shopItems = itemsByShop[shopId]
	local item = if shopItems then shopItems[itemId] else nil
	if not item then
		return false, Config.Text.InvalidRequest
	end

	local data = services.Data:Get(player)
	if not data then
		return false, Config.Text.NoData
	end
	if not isNearShop(player, shopId) then
		return false, Config.Text.TooFarFromShop
	end

	local permanent = item.Kind == "permanent"
	if permanent and data.Owned[item.Id] then
		return false, Config.Text.AlreadyOwned
	end

	-- Mọi kiểm tra đã qua: trừ tiền (nguyên tử) rồi trao đồ, không yield ở giữa
	if not services.Economy:TrySpend(player, item.Price, Config.Reasons.Shop) then
		return false, Config.Text.NotEnoughMoney
	end

	local price = Format.money(item.Price)
	local message: string
	if permanent then
		data.Owned[item.Id] = true
		message = string.format(Config.Text.BoughtPermanent, item.Name, price, item.Fame or 0)
	else
		services.Stats:Modify(player, item.Effects or {})
		message = string.format(Config.Text.BoughtConsumable, item.Name, price)
	end

	services.Replication:MarkDirty(player)
	return true, message
end

return ShopService
