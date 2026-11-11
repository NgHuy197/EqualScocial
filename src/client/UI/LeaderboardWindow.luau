--!strict
--[[
	LeaderboardWindow.luau — panel bảng xếp hạng tài sản (dựng bằng code).

	  * Open(): hiện panel, lấy dữ liệu từ server qua `fetch` (RemoteFunction GetLeaderboard) rồi vẽ top 50.
	  * Dòng của chính người chơi được tô nổi; chân panel luôn ghi hạng và tài sản ròng của bạn.
	  * Tự đóng khi đi xa bảng quá Config.Leaderboard.PanelCloseDistance.
	Client chỉ HIỂN THỊ dữ liệu server trả về; không tự tính hạng hay tài sản.
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

type View = Types.LeaderboardView

type Fields = {
	Root: Frame,
	Status: TextLabel,
	List: ScrollingFrame,
	Footer: TextLabel,
	Anchor: BasePart?,
	FallbackPosition: Vector3?, -- dùng khi không tìm thấy điểm neo phía client
	Elapsed: number,
	Monitor: RBXScriptConnection?,
	Token: number, -- tăng mỗi lần mở/đóng để bỏ kết quả của lần mở cũ
	Fetch: () -> View?,
	OnAutoClose: () -> (),
}

local MONITOR_INTERVAL = 0.2
local ROW_HEIGHT = 34
local RANK_WIDTH = 56

local LeaderboardWindow = {}
LeaderboardWindow.__index = LeaderboardWindow

export type LeaderboardWindow = typeof(setmetatable({} :: Fields, LeaderboardWindow))

-- ───────────────────────────── Tiện ích ─────────────────────────────

local function getRootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Điểm neo phía client = part giữ ProximityPrompt của bảng (giống phía server); lấy bảng gần nhất
local function findAnchor(): BasePart?
	local root = getRootPart()
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, inst in CollectionService:GetTagged(Config.Tags.Leaderboard) do
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

-- ───────────────────────────── Dựng giao diện ─────────────────────────────

function LeaderboardWindow.new(
	parent: Instance,
	fetch: () -> View?,
	onAutoClose: () -> ()
): LeaderboardWindow
	local root = Instance.new("Frame")
	root.Name = "LeaderboardWindow"
	root.Visible = false
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(0.9, 0.85)
	root.BackgroundColor3 = Theme.Colors.Panel
	root.Parent = parent
	Theme.corner(root, 12)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(300, 300)
	constraint.MaxSize = Vector2.new(460, 580)
	constraint.Parent = root

	local title =
		Theme.label(root, Config.Text.LeaderboardTitle, 26, Theme.Colors.Text, Theme.Fonts.Bold)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -120, 0, 34)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(84, 34)
	closeButton.BackgroundColor3 = Theme.Colors.PanelLight
	closeButton.Font = Theme.Fonts.Bold
	closeButton.Text = Config.Text.LeaderboardClose
	closeButton.TextSize = 18
	closeButton.TextColor3 = Theme.Colors.Text
	closeButton.Parent = root
	Theme.corner(closeButton, 8)

	local status = Theme.label(root, "", 15, Theme.Colors.TextMuted)
	status.Position = UDim2.fromOffset(16, 46)
	status.Size = UDim2.new(1, -32, 0, 36)
	status.TextWrapped = true
	status.TextYAlignment = Enum.TextYAlignment.Top

	local list = Instance.new("ScrollingFrame")
	list.Name = "Entries"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(12, 84)
	list.Size = UDim2.new(1, -24, 1, -140)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local footer = Theme.label(root, "", 18, Theme.Colors.Fame, Theme.Fonts.Semibold)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 16, 1, -10)
	footer.Size = UDim2.new(1, -32, 0, 40)
	footer.TextWrapped = true

	local self = setmetatable({
		Root = root,
		Status = status,
		List = list,
		Footer = footer,
		Anchor = nil,
		FallbackPosition = nil,
		Elapsed = 0,
		Monitor = nil,
		Token = 0,
		Fetch = fetch,
		OnAutoClose = onAutoClose,
	}, LeaderboardWindow)

	closeButton.Activated:Connect(function()
		self:Close()
	end)

	return self
end

function LeaderboardWindow._clearRows(self: LeaderboardWindow)
	for _, child in self.List:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

function LeaderboardWindow._buildRow(
	self: LeaderboardWindow,
	entry: Types.LeaderboardEntry,
	isSelf: boolean
)
	local row = Instance.new("Frame")
	row.Name = `Rank{entry.Rank}`
	row.LayoutOrder = entry.Rank
	row.Size = UDim2.new(1, -6, 0, ROW_HEIGHT)
	row.BackgroundColor3 = if isSelf then Theme.Colors.Accent else Theme.Colors.PanelLight
	row.Parent = self.List
	Theme.corner(row, 6)

	local rank = Theme.label(row, `#{entry.Rank}`, 18, Theme.Colors.Fame, Theme.Fonts.Bold)
	rank.Position = UDim2.fromOffset(10, 0)
	rank.Size = UDim2.new(0, RANK_WIDTH, 1, 0)

	local name = Theme.label(row, entry.Name, 18, Theme.Colors.Text, Theme.Fonts.Semibold)
	name.Position = UDim2.fromOffset(10 + RANK_WIDTH, 0)
	name.Size = UDim2.new(1, -(10 + RANK_WIDTH + 130), 1, 0)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local worth =
		Theme.label(row, Format.money(entry.NetWorth), 18, Theme.Colors.Money, Theme.Fonts.Bold)
	worth.AnchorPoint = Vector2.new(1, 0)
	worth.Position = UDim2.new(1, -10, 0, 0)
	worth.Size = UDim2.new(0, 120, 1, 0)
	worth.TextXAlignment = Enum.TextXAlignment.Right
end

-- Vẽ dữ liệu server trả về (đã kiểm tra hình dạng ở init.client)
function LeaderboardWindow._render(self: LeaderboardWindow, view: View)
	self:_clearRows()

	local selfId = Players.LocalPlayer.UserId
	for _, entry in view.Entries do
		self:_buildRow(entry, entry.UserId == selfId)
	end

	local ago = math.max(0, math.floor(Workspace:GetServerTimeNow() - view.UpdatedAt))
	local status = string.format(Config.Text.LeaderboardUpdated, ago)
	if view.IsLocal then
		status ..= "\n" .. Config.Text.LeaderboardLocal
	end
	self.Status.Text = status

	local worth = Format.money(view.SelfNetWorth)
	local rank = view.SelfRank
	self.Footer.Text = if rank
		then string.format(Config.Text.LeaderboardYourRank, rank, worth)
		else string.format(
			Config.Text.LeaderboardYourRankNone,
			Config.Leaderboard.TopCount,
			worth
		)
end

-- ───────────────────────────── Đóng / mở ─────────────────────────────

function LeaderboardWindow._isNearBoard(self: LeaderboardWindow): boolean
	local root = getRootPart()
	if not root then
		return false -- chết hoặc chưa có nhân vật
	end
	local anchor = self.Anchor
	local target = if anchor and anchor.Parent then anchor.Position else self.FallbackPosition
	if not target then
		return true
	end
	return (root.Position - target).Magnitude <= Config.Leaderboard.PanelCloseDistance
end

function LeaderboardWindow._stopMonitor(self: LeaderboardWindow)
	local monitor = self.Monitor
	if monitor then
		monitor:Disconnect()
		self.Monitor = nil
	end
end

function LeaderboardWindow.IsOpen(self: LeaderboardWindow): boolean
	return self.Root.Visible
end

function LeaderboardWindow.Open(self: LeaderboardWindow)
	self:_stopMonitor()
	self:_clearRows()
	self.Status.Text = Config.Text.LeaderboardLoading
	self.Footer.Text = ""

	local root = getRootPart()
	self.Anchor = findAnchor()
	self.FallbackPosition = if root then root.Position else nil
	self.Root.Visible = true

	-- Đi xa thì tự đóng
	self.Elapsed = 0
	self.Monitor = RunService.Heartbeat:Connect(function(dt: number)
		self.Elapsed += dt
		if self.Elapsed < MONITOR_INTERVAL then
			return
		end
		self.Elapsed = 0
		if not self:_isNearBoard() then
			self:Close()
			self.OnAutoClose()
		end
	end)

	-- Lấy dữ liệu ở luồng riêng; bỏ kết quả nếu trong lúc chờ panel đã đóng hoặc mở lại
	self.Token += 1
	local token = self.Token
	task.spawn(function()
		local view = self.Fetch()
		if token ~= self.Token or not self.Root.Visible then
			return
		end
		if view then
			self:_render(view)
		else
			self.Status.Text = Config.Text.LeaderboardError
		end
	end)
end

function LeaderboardWindow.Close(self: LeaderboardWindow)
	self.Token += 1
	self:_stopMonitor()
	self.Root.Visible = false
	self.Anchor = nil
	self.FallbackPosition = nil
end

return LeaderboardWindow
