--!strict
--[[
	AuctionService — đấu giá tài sản hiếm (Config.Assets có Stock). Mỗi lúc chỉ MỘT phiên trong server.

	  * AURA mở phiên theo chu kỳ (AuraService gọi Open). Giá khởi điểm = StartPercent * giá thuê.
	  * Đặt giá phải cao hơn giá cao nhất ít nhất MinRaisePercent. Tiền KHÓA NGAY khi đặt giá
	    (EconomyService, lý do "auction"), kèm phí đặt giá BidFeePercent KHÔNG hoàn ("auction_fee").
	  * Bị vượt giá => hoàn tiền đã khóa ngay. Đặt giá trong AntiSnipeWindowSeconds cuối thì phiên được
	    cộng thêm AntiSnipeExtendSeconds giây (chống chốt phút chót).
	  * Hết giờ: người cao nhất nhận tài sản qua registry toàn cầu (AssetService.GrantRare, nguyên tử).
	    Tiền thắng đấu giá BỊ HỦY khỏi nền kinh tế. Hết kho trong lúc đấu giá => hoàn tiền (trừ phí).
	  * Tiền khóa được ghi vào dữ liệu người chơi (data.Aura.Escrow): thoát giữa chừng thì lần vào sau
	    được hoàn lại. Người dẫn đầu rời server => phiên bị hủy (những người bị vượt giá đã được hoàn).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validate = require(script.Parent.Parent.Util.Validate)

type Auction = {
	Id: string,
	AssetId: string,
	StartPrice: number,
	EndsAt: number, -- giờ server
	HighestBid: number, -- 0 nếu chưa ai đặt giá
	Bidder: Player?,
}

local AuctionBid = Remotes.Function("AuctionBid")

local services: Types.Services = {}
local current: Auction? = nil
local counter = 0
local limiter =
	RateLimiter.new(Config.RateLimits.AuctionBid.Calls, Config.RateLimits.AuctionBid.Window)

local AuctionService = {}

local function notifyAll(text: string)
	for _, player in Players:GetPlayers() do
		services.Replication:Notify(player, text, "aura")
	end
end

local function assetName(assetId: string): string
	local def = Config.Assets[assetId]
	return if def then def.Name else assetId
end

-- Giá tối thiểu của lần đặt kế tiếp
local function minNextBid(auction: Auction): number
	if auction.HighestBid <= 0 then
		return auction.StartPrice
	end
	return math.max(
		auction.HighestBid + 1,
		math.ceil(auction.HighestBid * (1 + Config.Auction.MinRaisePercent))
	)
end

-- ───────────────────────────── Vòng đời ─────────────────────────────

function AuctionService:Init(allServices: Types.Services)
	services = allServices
end

function AuctionService:Start()
	-- Lần vào game sau: hoàn tiền đặt giá bị khóa còn sót (đã thoát giữa chừng)
	services.Data:OnLoaded(function(player: Player, data: Types.PlayerData)
		local escrow = data.Aura.Escrow
		if not escrow then
			return
		end
		local auction = current
		if auction and auction.Id == escrow.AuctionId and auction.Bidder == player then
			return -- vẫn đang dẫn đầu phiên này
		end
		data.Aura.Escrow = nil
		local refunded = services.Economy:Add(player, escrow.Amount, Config.Reasons.AuctionRefund)
		if refunded > 0 then
			services.Replication:Notify(
				player,
				string.format(Config.Text.EscrowRefunded, Format.money(refunded)),
				"aura"
			)
		end
	end)

	-- Người dẫn đầu rời server: hủy phiên (tiền của họ nằm trong dữ liệu đã lưu, được hoàn khi vào lại)
	Players.PlayerRemoving:Connect(function(player: Player)
		local auction = current
		if auction and auction.Bidder == player then
			current = nil
			services.Aura:MarkDirty()
			notifyAll(string.format(Config.Text.AuctionCancelled, assetName(auction.AssetId)))
		end
	end)

	AuctionBid.OnServerInvoke = function(player: Player, amount: any)
		if not Validate.isPlayer(player) then
			return false, Config.Text.InvalidRequest
		end
		if not limiter:Allow(player) then
			return false, Config.Text.TooFast
		end
		if not Validate.isFiniteNumber(amount) then
			return false, Config.Text.InvalidRequest
		end
		if not services.Aura:IsNearHq(player) then
			return false, Config.Text.TooFarFromAura
		end
		local ok, success, message = pcall(function()
			return self:Bid(player, amount :: number)
		end)
		if not ok then
			warn(`[AuctionService] Lỗi đặt giá: {tostring(success)}`)
			return false, Config.Text.ServerError
		end
		return success, message
	end

	-- Vòng kiểm tra hết giờ (bọc pcall: một lỗi không làm dừng cả vòng)
	task.spawn(function()
		while true do
			task.wait(Config.Auction.CheckSeconds)
			local auction = current
			if auction and Workspace:GetServerTimeNow() >= auction.EndsAt then
				local ok, err = pcall(function()
					self:_settle()
				end)
				if not ok then
					warn(`[AuctionService] Lỗi chốt đấu giá: {tostring(err)}`)
				end
			end
		end
	end)
end

-- ───────────────────────────── API công khai ─────────────────────────────

function AuctionService:GetState(): Types.AuctionState?
	local auction = current
	if not auction then
		return nil
	end
	local bidder = auction.Bidder
	return {
		AssetId = auction.AssetId,
		HighestBid = auction.HighestBid,
		HighestBidderName = if bidder then bidder.Name else nil,
		StartPrice = auction.StartPrice,
		MinNextBid = minNextBid(auction),
		EndsAt = auction.EndsAt,
	}
end

-- Mở một phiên cho một tài sản hiếm còn kho. Có thể yield (đọc kho registry). Trả về true nếu đã mở.
function AuctionService:Open(): boolean
	if current then
		return false
	end
	local ids: { string } = {}
	for assetId, def in Config.Assets do
		if def.Stock ~= nil then
			table.insert(ids, assetId)
		end
	end
	table.sort(ids)

	local candidates: { string } = {}
	for _, assetId in ids do
		local remaining = services.Assets:GetRemaining(assetId)
		if remaining ~= nil and remaining > 0 then
			table.insert(candidates, assetId)
		end
	end

	if current then
		return false -- một phiên khác đã mở trong lúc đọc kho
	end
	if #candidates == 0 then
		notifyAll(Config.Text.AuctionNoStock)
		services.Aura:MarkDirty()
		return false
	end

	local assetId = candidates[math.random(1, #candidates)]
	local def = Config.Assets[assetId]
	counter += 1
	local startPrice = math.floor(def.Price * Config.Auction.StartPercent + 0.5)
	current = {
		Id = string.format("%s-%d", game.JobId, counter),
		AssetId = assetId,
		StartPrice = startPrice,
		EndsAt = Workspace:GetServerTimeNow() + Config.Auction.DurationSeconds,
		HighestBid = 0,
		Bidder = nil,
	}
	notifyAll(
		string.format(
			Config.Text.AuctionOpened,
			def.Name,
			Format.money(startPrice),
			Config.Auction.DurationSeconds
		)
	)
	services.Aura:MarkDirty()
	return true
end

-- Đặt giá. Trả về (thành công, thông báo). Không yield: kiểm tra, khóa tiền và ghi nằm trong một bước.
function AuctionService:Bid(player: Player, rawAmount: number): (boolean, string)
	local auction = current
	if not auction then
		return false, Config.Text.AuctionNone
	end
	local now = Workspace:GetServerTimeNow()
	if now >= auction.EndsAt then
		return false, Config.Text.AuctionEnded
	end
	local data = services.Data:Get(player)
	if not data then
		return false, Config.Text.NoData
	end
	if data.Assets[auction.AssetId] then
		return false, Config.Text.AuctionOwned
	end
	if auction.Bidder == player then
		return false, Config.Text.AuctionLeading
	end
	if data.Aura.Escrow ~= nil then
		return false, Config.Text.InvalidRequest -- còn tiền khóa chưa hoàn: không đặt giá chồng
	end

	local amount = math.floor(rawAmount)
	local minimum = minNextBid(auction)
	if amount < minimum then
		return false, string.format(Config.Text.AuctionBidTooLow, Format.money(minimum))
	end
	local fee = math.floor(amount * Config.Auction.BidFeePercent + 0.5)
	if services.Economy:Get(player) < amount + fee then
		return false, Config.Text.NotEnoughMoney
	end

	-- Đã kiểm tra đủ tiền cho cả giá và phí nên hai lần trừ dưới đây chắc chắn thành công
	services.Economy:TrySpend(player, amount, Config.Reasons.Auction)
	services.Economy:TrySpend(player, fee, Config.Reasons.AuctionFee)
	data.Aura.Escrow = { AuctionId = auction.Id, AssetId = auction.AssetId, Amount = amount }

	-- Hoàn tiền cho người bị vượt giá (nếu họ còn trong server; nếu không, lần vào sau sẽ được hoàn)
	local previous = auction.Bidder
	if previous then
		local previousData = services.Data:Get(previous)
		if previousData then
			services.Economy:Add(previous, auction.HighestBid, Config.Reasons.AuctionRefund)
			previousData.Aura.Escrow = nil
			services.Replication:Notify(
				previous,
				string.format(
					Config.Text.AuctionOutbid,
					assetName(auction.AssetId),
					Format.money(auction.HighestBid)
				),
				"aura"
			)
		end
	end

	auction.HighestBid = amount
	auction.Bidder = player
	-- Chống chốt phút chót
	if auction.EndsAt - now <= Config.Auction.AntiSnipeWindowSeconds then
		auction.EndsAt += Config.Auction.AntiSnipeExtendSeconds
	end
	services.Aura:MarkDirty()
	services.Replication:MarkDirty(player)
	return true,
		string.format(
			Config.Text.AuctionBidOk,
			Format.money(amount),
			assetName(auction.AssetId),
			Format.money(fee)
		)
end

-- ───────────────────────────── Nội bộ ─────────────────────────────

-- Chốt phiên đã hết giờ. Có thể yield (nhận tài sản qua registry).
function AuctionService:_settle()
	local auction = current
	if not auction then
		return
	end
	current = nil -- gỡ trước (đồng bộ) để không chốt hai lần
	services.Aura:MarkDirty()

	local name = assetName(auction.AssetId)
	local winner = auction.Bidder
	if not winner then
		notifyAll(string.format(Config.Text.AuctionNoWinner, name))
		return
	end
	if winner.Parent ~= Players then
		return -- đã rời: tiền khóa nằm trong dữ liệu đã lưu, hoàn khi vào lại
	end

	local granted = services.Assets:GrantRare(winner, auction.AssetId)
	local data = services.Data:Get(winner)
	if granted then
		if data then
			data.Aura.Escrow = nil -- tiền thắng đấu giá bị hủy khỏi nền kinh tế
		end
		local def = Config.Assets[auction.AssetId]
		services.Replication:Notify(
			winner,
			string.format(
				Config.Text.AuctionWon,
				name,
				Format.money(auction.HighestBid),
				if def then def.Fame else 0
			),
			"aura"
		)
		notifyAll(
			string.format(
				Config.Text.AuctionWonAnnounce,
				winner.Name,
				name,
				Format.money(auction.HighestBid)
			)
		)
	elseif data then
		-- Hết kho trong lúc đấu giá (server khác đã nhận): hoàn tiền đặt giá, phí đặt giá không hoàn
		services.Economy:Add(winner, auction.HighestBid, Config.Reasons.AuctionRefund)
		data.Aura.Escrow = nil
		services.Replication:Notify(
			winner,
			string.format(Config.Text.AuctionSoldOut, name, Format.money(auction.HighestBid)),
			"aura"
		)
	end
end

return AuctionService
