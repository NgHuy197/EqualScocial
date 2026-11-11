--!strict
--[[
	AuraWindow.luau — cửa sổ Trụ sở AURA (dựng bằng code), 3 tab:
	  * Tài sản : danh sách tài sản (nhà, xe) để thuê / trả lại, kèm phí duy trì và nợ.
	  * Đấu giá : phiên đấu giá tài sản hiếm đang diễn ra (hoặc thời điểm phiên kế tiếp).
	  * Báo cáo : "Báo cáo của AURA" — chu kỳ, sự kiện, hệ số chính sách, thuế, tiền trung bình, nhật ký.

	Client chỉ HIỂN THỊ trạng thái do server gửi (AuraUpdate / GetAuraState) và GỬI YÊU CẦU
	(thuê, trả, đặt giá); server luôn kiểm tra lại mọi thứ. Tự đóng khi đi xa Trụ sở.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Theme)

type AuraState = Types.AuraState

export type Callbacks = {
	Fetch: () -> Types.AuraView?,
	OnLease: (assetId: string) -> (),
	OnReturn: (assetId: string) -> (),
	OnBid: (amount: number) -> (),
	OnAutoClose: () -> (),
}

type Fields = {
	Root: Frame,
	TabButtons: { [string]: TextButton },
	Content: ScrollingFrame,
	Tab: string,
	Order: number, -- LayoutOrder kế tiếp trong vùng nội dung
	State: AuraState?,
	View: Types.AuraView?,
	Snapshot: Types.Snapshot?,
	Busy: boolean, -- đang chờ server trả lời một thao tác (chặn bấm liên tục)
	Anchor: BasePart?,
	FallbackPosition: Vector3?,
	Elapsed: number,
	TickElapsed: number,
	TimeLabel: TextLabel?, -- nhãn đếm ngược của phiên đấu giá (cập nhật tại chỗ, không dựng lại)
	SnapshotKey: string, -- tiền + tài sản của snapshot đã vẽ (bỏ qua snapshot không đổi gì)
	Monitor: RBXScriptConnection?,
	Token: number,
	Callbacks: Callbacks,
}

local TAB_ORDER = { "assets", "auction", "report" }
local MONITOR_INTERVAL = 0.2
local RENDER_INTERVAL = 1 -- vẽ lại mỗi giây để đồng hồ đếm ngược chạy
local ROW_HEIGHT = 92
local BID_STEP_UP = 1.25 -- nút đặt giá thứ hai = giá tối thiểu x hệ số này

local AuraWindow = {}
AuraWindow.__index = AuraWindow

export type AuraWindow = typeof(setmetatable({} :: Fields, AuraWindow))

-- ───────────────────────────── Tiện ích ─────────────────────────────

local function getRootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Điểm neo phía client = part giữ ProximityPrompt của Trụ sở (giống phía server); lấy cái gần nhất
local function findAnchor(): BasePart?
	local root = getRootPart()
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, inst in CollectionService:GetTagged(Config.Tags.Aura) do
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
	return best
end

-- Phí duy trì thực tế một tài sản (khớp công thức phía server: làm tròn sau khi nhân hệ số chính sách)
local function effectiveFee(def: Config.AssetDef, state: AuraState): number
	return math.floor(def.FeePerCycle * state.PolicyMultiplier + 0.5)
end

local function sortedAssetIds(): { string }
	local ids: { string } = {}
	for assetId in Config.Assets do
		table.insert(ids, assetId)
	end
	table.sort(ids, function(a: string, b: string)
		local left, right = Config.Assets[a], Config.Assets[b]
		if left.Price ~= right.Price then
			return left.Price < right.Price
		end
		return a < b
	end)
	return ids
end

local function kindText(kind: Config.AssetKind): string
	return if kind == "house" then Config.Text.AssetKindHouse else Config.Text.AssetKindVehicle
end

-- ───────────────────────────── Dựng giao diện ─────────────────────────────

function AuraWindow.new(parent: Instance, callbacks: Callbacks): AuraWindow
	local root = Instance.new("Frame")
	root.Name = "AuraWindow"
	root.Visible = false
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(0.92, 0.88)
	root.BackgroundColor3 = Theme.Colors.Panel
	root.Parent = parent
	Theme.corner(root, 12)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(320, 320)
	constraint.MaxSize = Vector2.new(520, 620)
	constraint.Parent = root

	local title =
		Theme.label(root, Config.Text.AuraTitle, 26, Theme.KindColors.aura, Theme.Fonts.Bold)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -120, 0, 34)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(84, 34)
	closeButton.BackgroundColor3 = Theme.Colors.PanelLight
	closeButton.Font = Theme.Fonts.Bold
	closeButton.Text = Config.Text.AuraClose
	closeButton.TextSize = 18
	closeButton.TextColor3 = Theme.Colors.Text
	closeButton.Parent = root
	Theme.corner(closeButton, 8)

	-- Thanh tab
	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.Position = UDim2.fromOffset(12, 50)
	tabBar.Size = UDim2.new(1, -24, 0, 36)
	tabBar.Parent = root
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabBar

	local tabText: { [string]: string } = {
		assets = Config.Text.AuraTabAssets,
		auction = Config.Text.AuraTabAuction,
		report = Config.Text.AuraTabReport,
	}
	local tabButtons: { [string]: TextButton } = {}
	for index, tabId in TAB_ORDER do
		local button = Instance.new("TextButton")
		button.Name = tabId
		button.LayoutOrder = index
		button.Size = UDim2.new(1 / #TAB_ORDER, -4, 1, 0)
		button.Font = Theme.Fonts.Bold
		button.Text = tabText[tabId]
		button.TextSize = 18
		button.TextColor3 = Theme.Colors.Text
		button.BackgroundColor3 = Theme.Colors.PanelLight
		button.Parent = tabBar
		Theme.corner(button, 8)
		tabButtons[tabId] = button
	end

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(12, 94)
	content.Size = UDim2.new(1, -24, 1, -106)
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content

	local self = setmetatable({
		Root = root,
		TabButtons = tabButtons,
		Content = content,
		Tab = "assets",
		Order = 0,
		State = nil,
		View = nil,
		Snapshot = nil,
		Busy = false,
		Anchor = nil,
		FallbackPosition = nil,
		Elapsed = 0,
		TickElapsed = 0,
		TimeLabel = nil,
		SnapshotKey = "",
		Monitor = nil,
		Token = 0,
		Callbacks = callbacks,
	}, AuraWindow)

	closeButton.Activated:Connect(function()
		self:Close()
	end)
	for tabId, button in tabButtons do
		button.Activated:Connect(function()
			self.Tab = tabId
			self:_render()
			if tabId == "report" then
				task.spawn(function()
					self:Refetch() -- thuế dự kiến phụ thuộc tài sản ròng hiện tại
				end)
			end
		end)
	end

	return self
end

function AuraWindow._clear(self: AuraWindow)
	for _, child in self.Content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.Order = 0
	self.TimeLabel = nil
end

function AuraWindow._nextOrder(self: AuraWindow): number
	self.Order += 1
	return self.Order
end

function AuraWindow._addLine(
	self: AuraWindow,
	text: string,
	color: Color3?,
	textSize: number?,
	font: Enum.Font?
): TextLabel
	local label = Theme.label(
		self.Content,
		text,
		textSize or 17,
		color or Theme.Colors.Text,
		font or Theme.Fonts.Regular
	)
	label.Size = UDim2.new(1, -8, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.LayoutOrder = self:_nextOrder()
	return label
end

-- Một hàng: tên + mô tả bên trái, nút bên phải (buttonText = nil thì không có nút)
function AuraWindow._addRow(
	self: AuraWindow,
	title: string,
	titleColor: Color3,
	info: string,
	buttonText: string?,
	enabled: boolean,
	onClick: (() -> ())?,
	key: string?
)
	local row = Instance.new("Frame")
	row.Name = key or "Row"
	row.LayoutOrder = self:_nextOrder()
	row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	row.BackgroundColor3 = Theme.Colors.PanelLight
	row.Parent = self.Content
	Theme.corner(row, 8)

	local name = Theme.label(row, title, 20, titleColor, Theme.Fonts.Bold)
	name.Position = UDim2.fromOffset(12, 6)
	name.Size = UDim2.new(1, -150, 0, 26)

	local detail = Theme.label(row, info, 15, Theme.Colors.TextMuted)
	detail.Position = UDim2.fromOffset(12, 34)
	detail.Size = UDim2.new(1, -150, 0, 52)
	detail.TextWrapped = true
	detail.TextYAlignment = Enum.TextYAlignment.Top

	if buttonText then
		local button = Instance.new("TextButton")
		button.Name = "Action"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -12, 0.5, 0)
		button.Size = UDim2.fromOffset(124, 44)
		button.Font = Theme.Fonts.Bold
		button.Text = buttonText
		button.TextSize = 17
		button.TextWrapped = true
		button.TextColor3 = Theme.Colors.Text
		button.BackgroundColor3 = if enabled then Theme.Colors.Accent else Theme.Colors.Disabled
		button.AutoButtonColor = enabled
		button.Parent = row
		Theme.corner(button, 8)
		if enabled and onClick then
			button.Activated:Connect(function()
				if self.Busy then
					return
				end
				self.Busy = true
				onClick() -- yield tới khi server trả lời
				self.Busy = false
				self:_render()
			end)
		end
	end
end

-- ───────────────────────────── Nội dung các tab ─────────────────────────────

function AuraWindow._renderAssets(self: AuraWindow, state: AuraState)
	local snapshot = self.Snapshot
	local leased: { [string]: number } = if snapshot then snapshot.Assets else {}
	local money = if snapshot then snapshot.Money else 0
	local view = self.View
	local stock: { [string]: number } = if view then view.Stock else {}

	local upkeep = 0
	for assetId in leased do
		local def = Config.Assets[assetId]
		if def then
			upkeep += effectiveFee(def, state)
		end
	end
	self:_addLine(
		string.format(Config.Text.AssetUpkeep, Format.money(upkeep)),
		Theme.Colors.Fame,
		17,
		Theme.Fonts.Semibold
	)

	for _, assetId in sortedAssetIds() do
		local def = Config.Assets[assetId]
		local fee = effectiveFee(def, state)
		local missed = leased[assetId]
		local info = string.format(
			Config.Text.AssetInfo,
			kindText(def.Kind),
			Format.money(def.Price),
			Format.money(fee),
			def.Fame
		)
		local stockLimit = def.Stock
		if stockLimit ~= nil then
			local remaining = stock[assetId]
			info ..= "\n" .. if remaining ~= nil
				then string.format(Config.Text.AssetStock, remaining, stockLimit)
				else Config.Text.AssetStockUnknown
		end

		if missed ~= nil then
			local tag = Config.Text.AssetLeasedTag
			if missed > 0 then
				tag = `{tag} · {string.format(Config.Text.AssetDebt, missed)}`
			end
			self:_addRow(
				`{def.Name} ({tag})`,
				if missed > 0 then Theme.Colors.Bad else Theme.Colors.Good,
				info,
				Config.Text.AssetReturnButton,
				true,
				function()
					self.Callbacks.OnReturn(assetId)
				end,
				assetId
			)
		elseif stockLimit ~= nil then
			self:_addRow(
				def.Name,
				Theme.Colors.Fame,
				info,
				Config.Text.AssetRareButton,
				false,
				nil,
				assetId
			)
		else
			self:_addRow(
				def.Name,
				Theme.Colors.Text,
				info,
				string.format(Config.Text.AssetLeaseButton, Format.money(def.Price)),
				money >= def.Price,
				function()
					self.Callbacks.OnLease(assetId)
				end,
				assetId
			)
		end
	end
end

function AuraWindow._renderAuction(self: AuraWindow, state: AuraState)
	local auction = state.Auction
	local now = Workspace:GetServerTimeNow()

	if not auction then
		self:_addLine(Config.Text.AuctionNone, Theme.Colors.Text, 18, Theme.Fonts.Semibold)
		local every = Config.Aura.AuctionEveryCycles
		local nextCycle = (math.floor(state.Cycle / every) + 1) * every
		local remaining = nextCycle * Config.Aura.CycleSeconds - now
		self:_addLine(
			string.format(Config.Text.AuctionNextAfter, Format.duration(remaining)),
			Theme.Colors.TextMuted
		)
		self:_addLine(
			string.format(
				Config.Text.AuctionFeeNote,
				math.floor(Config.Auction.BidFeePercent * 100 + 0.5)
			),
			Theme.Colors.TextMuted,
			15
		)
		return
	end

	local def = Config.Assets[auction.AssetId]
	local name = if def then def.Name else auction.AssetId
	self:_addLine(
		string.format(Config.Text.AuctionCurrent, name),
		Theme.KindColors.aura,
		22,
		Theme.Fonts.Bold
	)
	if def then
		self:_addLine(
			string.format(
				Config.Text.AssetInfo,
				kindText(def.Kind),
				Format.money(def.Price),
				Format.money(effectiveFee(def, state)),
				def.Fame
			),
			Theme.Colors.TextMuted,
			15
		)
	end
	if auction.HighestBid > 0 then
		self:_addLine(
			string.format(
				Config.Text.AuctionBidLine,
				Format.money(auction.HighestBid),
				auction.HighestBidderName or "?"
			),
			Theme.Colors.Money,
			18,
			Theme.Fonts.Semibold
		)
	else
		self:_addLine(
			string.format(Config.Text.AuctionNoBids, Format.money(auction.StartPrice)),
			Theme.Colors.Text,
			18
		)
	end
	self.TimeLabel = self:_addLine(
		string.format(Config.Text.AuctionTimeLeft, Format.duration(auction.EndsAt - now)),
		Theme.Colors.Fame,
		18,
		Theme.Fonts.Semibold
	)

	-- Hai mức đặt giá nhanh: giá tối thiểu và cao hơn 25%
	local snapshot = self.Snapshot
	local money = if snapshot then snapshot.Money else 0
	local owns = snapshot ~= nil and snapshot.Assets[auction.AssetId] ~= nil
	local leading = auction.HighestBidderName == Players.LocalPlayer.Name
	local amounts = { auction.MinNextBid, math.ceil(auction.MinNextBid * BID_STEP_UP) }
	for index, amount in amounts do
		local fee = math.floor(amount * Config.Auction.BidFeePercent + 0.5)
		local enabled = not owns and not leading and money >= amount + fee
		self:_addRow(
			string.format(Config.Text.AuctionBidButton, Format.money(amount)),
			Theme.Colors.Text,
			string.format(Config.Text.AuctionBidInfo, Format.money(fee), Format.money(amount + fee)),
			string.format(Config.Text.AuctionBidButton, Format.money(amount)),
			enabled,
			function()
				self.Callbacks.OnBid(amount)
			end,
			`Bid{index}`
		)
	end
	self:_addLine(
		string.format(
			Config.Text.AuctionFeeNote,
			math.floor(Config.Auction.BidFeePercent * 100 + 0.5)
		),
		Theme.Colors.TextMuted,
		15
	)
end

function AuraWindow._renderReport(self: AuraWindow, state: AuraState)
	local now = Workspace:GetServerTimeNow()
	local view = self.View

	self:_addLine(
		string.format(
			Config.Text.ReportCycle,
			state.Cycle,
			Format.duration(state.CycleEndsAt - now)
		),
		Theme.KindColors.aura,
		18,
		Theme.Fonts.Bold
	)

	local event = state.Event
	if event then
		self:_addLine(
			string.format(Config.Text.ReportEvent, event.Name, Format.duration(event.EndsAt - now)),
			Theme.Colors.Fame,
			17,
			Theme.Fonts.Semibold
		)
		self:_addLine(event.Detail, Theme.Colors.TextMuted, 15)
	else
		self:_addLine(Config.Text.ReportNoEvent, Theme.Colors.TextMuted)
	end

	self:_addLine(
		string.format(Config.Text.ReportPolicy, string.format("%.2f", state.PolicyMultiplier))
	)

	if state.TaxExempt then
		self:_addLine(Config.Text.ReportTaxExempt, Theme.Colors.Good)
	else
		local expected = if view then view.ExpectedTax else 0
		self:_addLine(
			string.format(
				Config.Text.ReportTax,
				Format.duration(state.NextTaxAt - now),
				Format.money(expected)
			)
		)
	end

	self:_addLine(
		string.format(
			Config.Text.ReportAvg,
			Format.money(state.AvgMoney),
			Format.money(Config.Aura.Inflation.TargetAvgMoney),
			state.OnlinePlayers
		)
	)
	self:_addLine(
		string.format(
			Config.Text.ReportFlow,
			Format.money(state.Inflow),
			Format.money(state.Outflow)
		)
	)

	-- Biểu thuế (phần vượt ngưỡng của từng bậc chịu thuế suất của bậc đó)
	self:_addLine(
		string.format(Config.Text.ReportBrackets, Config.Aura.TaxEveryCycles),
		Theme.Colors.TextMuted,
		15,
		Theme.Fonts.Bold
	)
	local lower = 0
	for _, bracket in Config.Aura.TaxBrackets do
		local percent = string.format("%.0f", bracket.Rate * 100)
		local line = if bracket.Upto == math.huge
			then string.format(Config.Text.ReportBracketAbove, Format.money(lower), percent)
			else string.format(
				Config.Text.ReportBracketUpto,
				Format.money(bracket.Upto),
				percent
			)
		self:_addLine(line, Theme.Colors.Text, 15)
		lower = bracket.Upto
	end

	if view and view.IsLocalRegistry then
		self:_addLine(Config.Text.ReportLocalRegistry, Theme.Colors.Warn, 14)
	end

	self:_addLine(Config.Text.ReportLog, Theme.Colors.TextMuted, 15, Theme.Fonts.Bold)
	if #state.Log == 0 then
		self:_addLine(Config.Text.ReportLogEmpty, Theme.Colors.TextMuted, 15)
	end
	for index = #state.Log, 1, -1 do -- mới nhất ở trên
		self:_addLine("  " .. state.Log[index].Text, Theme.Colors.Text, 15)
	end
end

function AuraWindow._render(self: AuraWindow)
	if not self.Root.Visible then
		return
	end
	for tabId, button in self.TabButtons do
		button.BackgroundColor3 = if tabId == self.Tab
			then Theme.Colors.Accent
			else Theme.Colors.PanelLight
	end

	local scroll = self.Content.CanvasPosition
	self:_clear()
	local state = self.State
	if not state then
		self:_addLine(Config.Text.AuraLoading, Theme.Colors.TextMuted)
		return
	end
	if self.Tab == "assets" then
		self:_renderAssets(state)
	elseif self.Tab == "auction" then
		self:_renderAuction(state)
	else
		self:_renderReport(state)
	end
	self.Content.CanvasPosition = scroll
end

-- ───────────────────────────── Đóng / mở / cập nhật ─────────────────────────────

function AuraWindow._isNearHq(self: AuraWindow): boolean
	local root = getRootPart()
	if not root then
		return false -- chết hoặc chưa có nhân vật
	end
	local anchor = self.Anchor
	local target = if anchor and anchor.Parent then anchor.Position else self.FallbackPosition
	if not target then
		return true
	end
	return (root.Position - target).Magnitude <= Config.Aura.PanelCloseDistance
end

function AuraWindow._stopMonitor(self: AuraWindow)
	local monitor = self.Monitor
	if monitor then
		monitor:Disconnect()
		self.Monitor = nil
	end
end

function AuraWindow.IsOpen(self: AuraWindow): boolean
	return self.Root.Visible
end

-- Nhận trạng thái chung mới từ server (AuraUpdate)
function AuraWindow.SetState(self: AuraWindow, state: AuraState)
	self.State = state
	self:_render()
end

-- Nhận snapshot mới của người chơi (tiền, tài sản đang thuê)
function AuraWindow.SetSnapshot(self: AuraWindow, snapshot: Types.Snapshot)
	self.Snapshot = snapshot
	-- Snapshot đến mỗi vài giây (chỉ số tụt); chỉ vẽ lại khi tiền hoặc tài sản đổi, tránh huỷ nút
	-- đang được bấm
	local parts = { tostring(snapshot.Money) }
	for assetId, missed in snapshot.Assets do
		table.insert(parts, `{assetId}:{missed}`)
	end
	table.sort(parts)
	local key = table.concat(parts, "|")
	if key == self.SnapshotKey then
		return
	end
	self.SnapshotKey = key
	self:_render()
end

-- Lấy lại phần riêng của người chơi (kho, thuế dự kiến) mà không làm đóng/mở lại cửa sổ
function AuraWindow.Refetch(self: AuraWindow)
	local view = self.Callbacks.Fetch()
	if view and self.Root.Visible then
		self.View = view
		self.State = view.State
		self:_render()
	end
end

function AuraWindow.Open(self: AuraWindow)
	self:_stopMonitor()
	local root = getRootPart()
	self.Anchor = findAnchor()
	self.FallbackPosition = if root then root.Position else nil
	self.Root.Visible = true
	self.Busy = false
	self:_render()

	-- Đi xa thì tự đóng; mỗi giây vẽ lại để đồng hồ đếm ngược chạy
	self.Elapsed = 0
	self.TickElapsed = 0
	self.Monitor = RunService.Heartbeat:Connect(function(dt: number)
		self.Elapsed += dt
		self.TickElapsed += dt
		if self.Elapsed >= MONITOR_INTERVAL then
			self.Elapsed = 0
			if not self:_isNearHq() then
				self:Close()
				self.Callbacks.OnAutoClose()
				return
			end
		end
		if self.TickElapsed >= RENDER_INTERVAL and not self.Busy then
			self.TickElapsed = 0
			-- Chỉ tab Báo cáo (không có nút) mới dựng lại; tab Đấu giá chỉ cập nhật nhãn đếm ngược,
			-- để nút không bị huỷ giữa lúc người chơi đang bấm
			local state = self.State
			local timeLabel = self.TimeLabel
			if self.Tab == "report" then
				self:_render()
			elseif timeLabel and state and state.Auction then
				timeLabel.Text = string.format(
					Config.Text.AuctionTimeLeft,
					Format.duration(state.Auction.EndsAt - Workspace:GetServerTimeNow())
				)
			end
		end
	end)

	-- Lấy phần riêng của người chơi ở luồng riêng; bỏ kết quả nếu cửa sổ đã đóng hoặc mở lại
	self.Token += 1
	local token = self.Token
	task.spawn(function()
		local view = self.Callbacks.Fetch()
		if token ~= self.Token or not self.Root.Visible then
			return
		end
		if view then
			self.View = view
			self.State = view.State
			self:_render()
		elseif not self.State then
			self:_clear()
			self:_addLine(Config.Text.AuraError, Theme.Colors.Bad)
		end
	end)
end

function AuraWindow.Close(self: AuraWindow)
	self.Token += 1
	self:_stopMonitor()
	self.Root.Visible = false
	self.Anchor = nil
	self.FallbackPosition = nil
	self.Busy = false
end

return AuraWindow
