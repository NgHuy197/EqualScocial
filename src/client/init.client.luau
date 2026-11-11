--!strict
--[[
	Bootstrap client của Equal Social.

	Client CHỈ hiển thị: nhận snapshot từ server (StateUpdate / GetState) rồi vẽ HUD, toast và cửa sổ
	cửa hàng. Không có logic tiền/chỉ số nào ở đây; nút Mua chỉ gửi yêu cầu, server quyết định.
]]

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Chờ thư mục Shared replicate đủ trước khi require
local Shared = ReplicatedStorage:WaitForChild("Shared")
for _, name in { "Calendar", "Config", "Format", "Remotes", "Types" } do
	Shared:WaitForChild(name)
end

local Calendar = require(ReplicatedStorage.Shared.Calendar)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local AuraWindow = require(script.UI.AuraWindow)
local HUD = require(script.UI.HUD)
local LeaderboardWindow = require(script.UI.LeaderboardWindow)
local ProfileWindow = require(script.UI.ProfileWindow)
local ShopWindow = require(script.UI.ShopWindow)
local Toast = require(script.UI.Toast)

local GET_STATE_ATTEMPTS = 3
local GET_STATE_RETRY_DELAY = 3

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- IgnoreGuiInset = false: giữ HUD nằm dưới thanh menu của Roblox
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EqualSocialUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local state: Types.Snapshot? = nil
local shopBuy = Remotes.Function("ShopBuy")

local hud = HUD.new(screenGui)
local toast = Toast.new(screenGui)

-- Gửi yêu cầu mua; kết quả (thành công hay không) hiển thị bằng toast. Yield tới khi server trả lời.
local function requestBuy(shopId: string, itemId: string)
	local ok, success, message = pcall(function()
		return shopBuy:InvokeServer(shopId, itemId)
	end)
	if not ok then
		toast:Show(Config.Text.ShopNetworkError, "error")
		return
	end
	local text = if type(message) == "string" then message else Config.Text.ServerError
	toast:Show(text, if success == true then "success" else "warning")
end

local shopWindow = ShopWindow.new(screenGui, requestBuy, function()
	toast:Show(Config.Text.ShopAutoClosed, "info")
end)

-- Lấy bảng xếp hạng từ server; nil nếu lỗi mạng hoặc bị rate-limit
local getLeaderboard = Remotes.Function("GetLeaderboard")
local function fetchLeaderboard(): Types.LeaderboardView?
	local ok, view = pcall(function()
		return getLeaderboard:InvokeServer()
	end)
	if ok and type(view) == "table" and type(view.Entries) == "table" then
		return view :: Types.LeaderboardView
	end
	return nil
end

local leaderboardWindow = LeaderboardWindow.new(screenGui, fetchLeaderboard, function()
	toast:Show(Config.Text.LeaderboardAutoClosed, "info")
end)

-- ── AURA (v0.3) ──
local assetLease = Remotes.Function("AssetLease")
local assetReturn = Remotes.Function("AssetReturn")
local auctionBid = Remotes.Function("AuctionBid")
local getAuraState = Remotes.Function("GetAuraState")
local auraState: Types.AuraState? = nil

-- Gửi một yêu cầu (thuê / trả / đặt giá) rồi hiện kết quả bằng toast. Yield tới khi server trả lời.
local function requestAction(remote: RemoteFunction, argument: any)
	local ok, success, message = pcall(function()
		return remote:InvokeServer(argument)
	end)
	if not ok then
		toast:Show(Config.Text.ShopNetworkError, "error")
		return
	end
	local text = if type(message) == "string" then message else Config.Text.ServerError
	toast:Show(text, if success == true then "success" else "warning")
end

local function fetchAura(): Types.AuraView?
	local ok, view = pcall(function()
		return getAuraState:InvokeServer()
	end)
	if ok and type(view) == "table" and type(view.State) == "table" then
		return view :: Types.AuraView
	end
	return nil
end

local auraWindow: AuraWindow.AuraWindow
auraWindow = AuraWindow.new(screenGui, {
	Fetch = fetchAura,
	OnLease = function(assetId: string)
		requestAction(assetLease, assetId)
		auraWindow:Refetch()
	end,
	OnReturn = function(assetId: string)
		requestAction(assetReturn, assetId)
		auraWindow:Refetch()
	end,
	OnBid = function(amount: number)
		requestAction(auctionBid, amount)
		auraWindow:Refetch()
	end,
	OnAutoClose = function()
		toast:Show(Config.Text.AuraAutoClosed, "info")
	end,
})

-- Dòng AURA trên HUD: sự kiện đang chạy và thời gian còn lại
local function updateAuraHud()
	local current = auraState
	local event = if current then current.Event else nil
	if event then
		local remaining = Format.duration(event.EndsAt - Workspace:GetServerTimeNow())
		hud:SetAura(string.format(Config.Text.HudAuraEvent, event.Name, remaining))
	else
		hud:SetAura(Config.Text.HudAuraNone)
	end
end

-- ── Hồ sơ: danh hiệu và lịch sử mùa ──
local getProfile = Remotes.Function("GetProfile")
local function fetchProfile(): Types.ProfileView?
	local ok, view = pcall(function()
		return getProfile:InvokeServer()
	end)
	if ok and type(view) == "table" and type(view.History) == "table" then
		return view :: Types.ProfileView
	end
	return nil
end

local equipCosmetic = Remotes.Function("EquipCosmetic")
local equipTitle = Remotes.Function("EquipTitle")
local profileWindow: ProfileWindow.ProfileWindow
profileWindow = ProfileWindow.new(screenGui, {
	Fetch = fetchProfile,
	OnEquip = function(id: string)
		requestAction(equipCosmetic, id)
		profileWindow:Refetch()
	end,
	OnEquipTitle = function(title: string)
		requestAction(equipTitle, title)
		profileWindow:Refetch()
	end,
	OnBuy = function(gamePassId: number)
		-- Hộp thoại mua của Roblox; server tự cập nhật quyền sở hữu khi mua xong
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, gamePassId)
	end,
})
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _passId, purchased)
	if player == Players.LocalPlayer and purchased then
		task.wait(1) -- chờ server ghi nhận quyền sở hữu
		profileWindow:Refetch()
	end
end)

-- Mở hồ sơ thì đóng các cửa sổ khác (chỉ một cửa sổ mở cùng lúc)
local function toggleProfile()
	if not profileWindow:IsOpen() then
		shopWindow:Close()
		leaderboardWindow:Close()
		auraWindow:Close()
	end
	profileWindow:Toggle()
end

hud.ProfileButton.Activated:Connect(toggleProfile)
ContextActionService:BindAction(
	"EqualSocialProfile",
	function(_name, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			toggleProfile()
		end
		return Enum.ContextActionResult.Pass
	end,
	false,
	Enum.KeyCode.P
)

-- ── Mùa và Đấu trường (v0.4) ──
local pvpAttack = Remotes.Event("PvpAttack")
local pvpState: Types.PvpState = { State = "idle" }
local PVP_ACTION = "EqualSocialPvpAttack"
local pvpBound = false

-- Dòng mùa: tên, thời gian còn lại tới EndsAt (giờ server), điểm PvP, danh hiệu mới nhất
local function updateSeasonHud()
	local current = state
	if not current then
		return
	end
	local season = current.Season
	local remaining = season.EndsAt - Workspace:GetServerTimeNow()
	local text
	if remaining > 0 then
		local days = math.floor(remaining / 86400)
		local left = if days >= 1
			then string.format(Config.Text.SeasonDays, days)
			else string.format(
				Config.Text.SeasonHours,
				math.max(1, math.ceil(remaining / 3600))
			)
		text = string.format(Config.Text.HudSeason, season.Name, left, season.Pvp.Rating)
	else
		text = string.format(Config.Text.HudSeasonEnded, season.Name, season.Pvp.Rating)
	end
	if season.Title then
		text ..= "\n" .. season.Title
	end
	hud:SetSeason(text)
end

local function updatePvpHud()
	local current = pvpState
	if current.State == "queue" then
		hud:SetPvp(Config.Text.PvpHudQueue)
	elseif current.State == "countdown" then
		local wait = math.max(0, math.ceil((current.StartsAt or 0) - Workspace:GetServerTimeNow()))
		hud:SetPvp(string.format(Config.Text.PvpHudCountdown, current.OpponentName or "?", wait))
	elseif current.State == "fight" then
		local remaining = Format.duration((current.EndsAt or 0) - Workspace:GetServerTimeNow())
		hud:SetPvp(
			string.format(
				Config.Text.PvpHudFight,
				current.MyHP or 0,
				current.OpponentHP or 0,
				current.OpponentName or "?",
				remaining
			)
		)
	else
		hud:SetPvp(nil)
	end
end

-- Phím F (và nút "Đánh" trên điện thoại) chỉ gắn khi đang trong pha đánh. Client chỉ GỬI yêu cầu;
-- server kiểm tra trận, nhịp đánh và khoảng cách.
local function setAttackBinding(enabled: boolean)
	if enabled == pvpBound then
		return
	end
	pvpBound = enabled
	if enabled then
		ContextActionService:BindAction(PVP_ACTION, function(_name, inputState: Enum.UserInputState)
			if inputState == Enum.UserInputState.Begin then
				pvpAttack:FireServer()
			end
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
		ContextActionService:SetTitle(PVP_ACTION, Config.Text.PvpAttackButton)
	else
		ContextActionService:UnbindAction(PVP_ACTION)
	end
end

Remotes.Event("PvpUpdate").OnClientEvent:Connect(function(newState: any)
	if type(newState) ~= "table" or type(newState.State) ~= "string" then
		return
	end
	pvpState = newState :: Types.PvpState
	setAttackBinding(pvpState.State == "fight")
	updatePvpHud()
end)

-- Chỉ áp dụng snapshot mới hơn bản hiện có (GetState và StateUpdate có thể đến lệch thứ tự)
local function applySnapshot(snapshot: any)
	if type(snapshot) ~= "table" or type(snapshot.Seq) ~= "number" then
		return
	end
	local current = state
	if current and snapshot.Seq <= current.Seq then
		return
	end
	local typed = snapshot :: Types.Snapshot
	state = typed
	hud:Render(typed)
	shopWindow:Refresh(typed)
	auraWindow:SetSnapshot(typed)
	updateSeasonHud()
end

Remotes.Event("StateUpdate").OnClientEvent:Connect(applySnapshot)

Remotes.Event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
	if type(text) == "string" then
		toast:Show(text, if type(kind) == "string" then kind else nil)
	end
end)

Remotes.Event("OpenShop").OnClientEvent:Connect(function(shopId: any)
	if type(shopId) == "string" and Config.Shops[shopId] then
		leaderboardWindow:Close() -- chỉ một cửa sổ mở cùng lúc
		auraWindow:Close()
		profileWindow:Close()
		shopWindow:Open(shopId, state)
	end
end)

Remotes.Event("OpenLeaderboard").OnClientEvent:Connect(function()
	shopWindow:Close()
	auraWindow:Close()
	profileWindow:Close()
	leaderboardWindow:Open()
end)

Remotes.Event("OpenAura").OnClientEvent:Connect(function()
	shopWindow:Close()
	leaderboardWindow:Close()
	profileWindow:Close()
	auraWindow:Open()
end)

Remotes.Event("AuraUpdate").OnClientEvent:Connect(function(newState: any)
	if type(newState) ~= "table" or type(newState.Cycle) ~= "number" then
		return
	end
	local typed = newState :: Types.AuraState
	auraState = typed
	shopWindow:SetPriceMultipliers(typed.PriceMultipliers or {})
	auraWindow:SetState(typed)
	updateAuraHud()
end)

-- Dòng "Hôm nay: ..." trên HUD: ngày game suy ra từ giờ server, chỉ cập nhật khi đổi ngày
task.spawn(function()
	local shownDay = 0
	while true do
		local day = Calendar.GetWeekday(Workspace:GetServerTimeNow())
		if day ~= shownDay then
			shownDay = day
			hud:SetDay(string.format(Config.Text.HudDay, Calendar.DayName(day)))
		end
		updateAuraHud()
		updateSeasonHud()
		updatePvpHud()
		task.wait(1)
	end
end)

-- Lấy trạng thái lúc mới vào (server chờ dữ liệu tải xong rồi mới trả lời)
task.spawn(function()
	local getState = Remotes.Function("GetState")
	for attempt = 1, GET_STATE_ATTEMPTS do
		local ok, result = pcall(function()
			return getState:InvokeServer()
		end)
		if ok and result then
			applySnapshot(result)
			return
		end
		if attempt < GET_STATE_ATTEMPTS then
			task.wait(GET_STATE_RETRY_DELAY)
		end
	end
	warn("[EqualSocial] Không lấy được trạng thái ban đầu từ server.")
end)
