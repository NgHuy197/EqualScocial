--!strict
--[[
	Bootstrap client của Equal Social.

	Client CHỈ hiển thị: nhận snapshot từ server (StateUpdate / GetState) rồi vẽ HUD, toast và cửa sổ
	cửa hàng. Không có logic tiền/chỉ số nào ở đây; nút Mua chỉ gửi yêu cầu, server quyết định.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Chờ thư mục Shared replicate đủ trước khi require
local Shared = ReplicatedStorage:WaitForChild("Shared")
for _, name in { "Config", "Format", "Remotes", "Types" } do
	Shared:WaitForChild(name)
end

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local HUD = require(script.UI.HUD)
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
end

Remotes.Event("StateUpdate").OnClientEvent:Connect(applySnapshot)

Remotes.Event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
	if type(text) == "string" then
		toast:Show(text, if type(kind) == "string" then kind else nil)
	end
end)

Remotes.Event("OpenShop").OnClientEvent:Connect(function(shopId: any)
	if type(shopId) == "string" and Config.Shops[shopId] then
		shopWindow:Open(shopId, state)
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
