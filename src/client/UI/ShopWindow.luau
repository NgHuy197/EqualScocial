--!strict
--[[
	ShopWindow.luau — cửa sổ cửa hàng (dựng bằng code).

	  * Open(shopId, state): hiện danh sách món từ Config.Shops[shopId].Items.
	  * Mỗi món: tên, mô tả hiệu ứng (tự sinh từ Effects/Fame), nút Mua; đồ vĩnh viễn đã có => "Đã sở hữu".
	  * Tự đóng khi người chơi đi xa quá Config.ShopRules.CloseDistance so với cửa hàng.
	  * Nút Mua chỉ GỬI YÊU CẦU (onBuy). Server mới là nơi quyết định: client ẩn/hiện nút chỉ để cho đẹp.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Theme)

type ItemDef = Config.ItemDef

type ItemRow = {
	Item: ItemDef,
	Button: TextButton,
	Pending: boolean, -- đang chờ server trả lời
}

type Fields = {
	Root: Frame,
	Title: TextLabel,
	MoneyLabel: TextLabel,
	List: ScrollingFrame,
	Rows: { ItemRow },
	ShopId: string?,
	Anchor: BasePart?,
	FallbackPosition: Vector3?, -- dùng khi không tìm thấy điểm neo phía client
	State: Types.Snapshot?,
	PriceMultipliers: { [string]: number }, -- hệ số giá theo nhóm hàng do sự kiện AURA đặt
	Elapsed: number,
	Monitor: RBXScriptConnection?,
	OnBuy: (shopId: string, itemId: string) -> (),
	OnAutoClose: () -> (),
}

local MONITOR_INTERVAL = 0.2
local ROW_HEIGHT = 84

local ShopWindow = {}
ShopWindow.__index = ShopWindow

export type ShopWindow = typeof(setmetatable({} :: Fields, ShopWindow))

-- ───────────────────────────── Tiện ích ─────────────────────────────

local function getRootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Điểm neo phía client = part đang giữ ProximityPrompt của cửa hàng (giống phía server).
-- Nếu có nhiều cửa hàng cùng ShopId, lấy cái gần người chơi nhất.
local function findAnchor(shopId: string): BasePart?
	local root = getRootPart()
	local best: BasePart? = nil
	local bestDistance = math.huge

	for _, inst in CollectionService:GetTagged(Config.Tags.Shop) do
		if inst:GetAttribute(Config.Attributes.Shop) == shopId then
			local part: BasePart? = nil
			if inst:IsA("BasePart") then
				part = inst
			else
				local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
				local holder = if prompt then prompt.Parent else nil
				if holder and holder:IsA("BasePart") then
					part = holder
				end
			end
			if part then
				local distance = if root then (part.Position - root.Position).Magnitude else 0
				if distance < bestDistance then
					best = part
					bestDistance = distance
				end
			end
		end
	end
	return best
end

-- "Độ no +30 · Hạnh phúc +5" hoặc "Nổi tiếng +5 · Sở hữu vĩnh viễn"
local function describe(item: ItemDef): string
	if item.Description then
		return item.Description
	end
	local parts: { string } = {}
	if item.Kind == "permanent" then
		table.insert(parts, string.format(Config.Text.ShopFameLine, item.Fame or 0))
		table.insert(parts, Config.Text.ShopTagPermanent)
	elseif item.Effects then
		for _, statId in Config.Stats.Order do
			local delta = item.Effects[statId]
			if delta and delta ~= 0 then
				local sign = if delta > 0 then "+" else "-"
				table.insert(parts, `{Config.Stats.Defs[statId].Name} {sign}{math.abs(delta)}`)
			end
		end
	end
	return table.concat(parts, " · ")
end

-- ───────────────────────────── Dựng giao diện ─────────────────────────────

function ShopWindow.new(
	parent: Instance,
	onBuy: (shopId: string, itemId: string) -> (),
	onAutoClose: () -> ()
): ShopWindow
	local root = Instance.new("Frame")
	root.Name = "ShopWindow"
	root.Visible = false
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(0.9, 0.8)
	root.BackgroundColor3 = Theme.Colors.Panel
	root.Parent = parent
	Theme.corner(root, 12)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(300, 280)
	constraint.MaxSize = Vector2.new(460, 540)
	constraint.Parent = root

	local title = Theme.label(root, "", 26, Theme.Colors.Text, Theme.Fonts.Bold)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -120, 0, 34)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(84, 34)
	closeButton.BackgroundColor3 = Theme.Colors.PanelLight
	closeButton.Font = Theme.Fonts.Bold
	closeButton.Text = Config.Text.ShopClose
	closeButton.TextSize = 18
	closeButton.TextColor3 = Theme.Colors.Text
	closeButton.Parent = root
	Theme.corner(closeButton, 8)

	local moneyLabel = Theme.label(root, "", 18, Theme.Colors.Money, Theme.Fonts.Semibold)
	moneyLabel.Position = UDim2.fromOffset(16, 48)
	moneyLabel.Size = UDim2.new(1, -32, 0, 24)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Items"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(12, 82)
	list.Size = UDim2.new(1, -24, 1, -94)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local self = setmetatable({
		Root = root,
		Title = title,
		MoneyLabel = moneyLabel,
		List = list,
		Rows = {},
		ShopId = nil,
		Anchor = nil,
		FallbackPosition = nil,
		State = nil,
		PriceMultipliers = {},
		Elapsed = 0,
		Monitor = nil,
		OnBuy = onBuy,
		OnAutoClose = onAutoClose,
	}, ShopWindow)

	closeButton.Activated:Connect(function()
		self:Close()
	end)

	return self
end

function ShopWindow._clearRows(self: ShopWindow)
	for _, child in self.List:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(self.Rows)
end

function ShopWindow._buildRow(self: ShopWindow, item: ItemDef, order: number)
	local frame = Instance.new("Frame")
	frame.Name = item.Id
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, -6, 0, ROW_HEIGHT)
	frame.BackgroundColor3 = Theme.Colors.PanelLight
	frame.Parent = self.List
	Theme.corner(frame, 8)

	local name = Theme.label(frame, item.Name, 22, Theme.Colors.Text, Theme.Fonts.Bold)
	name.Position = UDim2.fromOffset(12, 8)
	name.Size = UDim2.new(1, -150, 0, 26)

	local description = Theme.label(frame, describe(item), 16, Theme.Colors.TextMuted)
	description.Position = UDim2.fromOffset(12, 36)
	description.Size = UDim2.new(1, -150, 0, 40)
	description.TextWrapped = true
	description.TextYAlignment = Enum.TextYAlignment.Top

	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Size = UDim2.fromOffset(120, 44)
	button.Font = Theme.Fonts.Bold
	button.TextSize = 19
	button.TextColor3 = Theme.Colors.Text
	button.BackgroundColor3 = Theme.Colors.Accent
	button.Parent = frame
	Theme.corner(button, 8)

	local row: ItemRow = { Item = item, Button = button, Pending = false }
	table.insert(self.Rows, row)

	button.Activated:Connect(function()
		local shopId = self.ShopId
		local state = self.State
		if not shopId or row.Pending then
			return
		end
		-- Chỉ để đỡ gửi yêu cầu thừa; server vẫn tự kiểm tra lại mọi thứ
		if item.Kind == "permanent" and state and state.Owned[item.Id] then
			return
		end
		row.Pending = true
		self:_refreshButtons()
		self.OnBuy(shopId, item.Id) -- yield tới khi server trả lời
		row.Pending = false
		self:_refreshButtons()
	end)
end

-- Giá hiển thị = giá gốc x hệ số sự kiện của nhóm hàng (server mới là nơi quyết định giá thật khi mua)
function ShopWindow._priceOf(self: ShopWindow, item: ItemDef): number
	local shopId = self.ShopId
	local shop = if shopId then Config.Shops[shopId] else nil
	local multiplier = if shop then self.PriceMultipliers[shop.Category] or 1 else 1
	return math.floor(item.Price * multiplier + 0.5)
end

-- Cập nhật hệ số giá từ trạng thái AURA
function ShopWindow.SetPriceMultipliers(self: ShopWindow, multipliers: { [string]: number })
	self.PriceMultipliers = multipliers
	if self.Root.Visible then
		self:_refreshButtons()
	end
end

function ShopWindow._refreshButtons(self: ShopWindow)
	local state = self.State
	for _, row in self.Rows do
		local item = row.Item
		local button = row.Button
		local owned = item.Kind == "permanent" and state ~= nil and state.Owned[item.Id] == true
		if owned then
			button.Text = Config.Text.ShopOwned
			button.BackgroundColor3 = Theme.Colors.Disabled
			button.AutoButtonColor = false
		elseif row.Pending then
			button.Text = Config.Text.ShopBuying
			button.BackgroundColor3 = Theme.Colors.Disabled
			button.AutoButtonColor = false
		else
			local price: number = self:_priceOf(item)
			local affordable = state ~= nil and state.Money >= price
			button.Text = string.format(Config.Text.ShopBuy, Format.money(price))
			button.BackgroundColor3 = if affordable
				then Theme.Colors.Accent
				else Theme.Colors.Disabled
			button.AutoButtonColor = affordable
		end
	end
	if state then
		self.MoneyLabel.Text = string.format(Config.Text.ShopYourMoney, Format.money(state.Money))
	end
end

-- ───────────────────────────── Đóng / mở ─────────────────────────────

function ShopWindow._isNearShop(self: ShopWindow): boolean
	local root = getRootPart()
	if not root then
		return false -- chết hoặc chưa có nhân vật
	end
	local anchor = self.Anchor
	local target = if anchor and anchor.Parent then anchor.Position else self.FallbackPosition
	if not target then
		return true
	end
	return (root.Position - target).Magnitude <= Config.ShopRules.CloseDistance
end

function ShopWindow._stopMonitor(self: ShopWindow)
	local monitor = self.Monitor
	if monitor then
		monitor:Disconnect()
		self.Monitor = nil
	end
end

function ShopWindow.IsOpen(self: ShopWindow): boolean
	return self.Root.Visible
end

function ShopWindow.Open(self: ShopWindow, shopId: string, state: Types.Snapshot?)
	local shop = Config.Shops[shopId]
	if not shop then
		return
	end

	self:_stopMonitor()
	self:_clearRows()

	self.ShopId = shopId
	self.State = state
	self.Title.Text = shop.Name
	for index, item in shop.Items do
		self:_buildRow(item, index)
	end
	self:_refreshButtons()

	local root = getRootPart()
	self.Anchor = findAnchor(shopId)
	self.FallbackPosition = if root then root.Position else nil
	self.Root.Visible = true

	-- Theo dõi khoảng cách: đi xa thì tự đóng
	self.Elapsed = 0
	self.Monitor = RunService.Heartbeat:Connect(function(dt: number)
		self.Elapsed += dt
		if self.Elapsed < MONITOR_INTERVAL then
			return
		end
		self.Elapsed = 0
		if not self:_isNearShop() then
			self:Close()
			self.OnAutoClose()
		end
	end)
end

function ShopWindow.Close(self: ShopWindow)
	self:_stopMonitor()
	self.Root.Visible = false
	self.ShopId = nil
	self.Anchor = nil
	self.FallbackPosition = nil
end

-- Gọi mỗi khi có snapshot mới để cập nhật nút Mua / số tiền
function ShopWindow.Refresh(self: ShopWindow, state: Types.Snapshot)
	self.State = state
	if self.Root.Visible then
		self:_refreshButtons()
	end
end

return ShopWindow
