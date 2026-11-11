--!strict
--[[
	Remotes.luau — khai báo và truy cập RemoteEvent / RemoteFunction.

	  Server : gọi Remotes.Init() MỘT lần lúc khởi động để tạo toàn bộ remote.
	  Server/Client : Remotes.Event("Tên") / Remotes.Function("Tên") để lấy remote.

	Danh sách tên nằm cứng ở đây để gõ sai tên sẽ báo lỗi ngay thay vì treo vô hạn.

	QUY TẮC AN TOÀN: dữ liệu từ client luôn là "không đáng tin" — handler phía server
	phải tự validate kiểu, giá trị, khoảng cách và rate-limit (xem Util/Validate, Util/RateLimiter).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local WAIT_TIMEOUT = 30

-- Server -> Client
--   StateUpdate(snapshot)   : snapshot trạng thái (tiền, chỉ số, skill, đồ, nổi tiếng)
--   Notify(text, kind)      : thông báo toast
--   OpenShop(shopId)        : mở cửa sổ cửa hàng sau khi ProximityPrompt kích hoạt
--   OpenLeaderboard()       : mở panel bảng xếp hạng sau khi ProximityPrompt của bảng kích hoạt
--   OpenAura()              : mở cửa sổ Trụ sở AURA sau khi ProximityPrompt kích hoạt
--   AuraUpdate(auraState)   : trạng thái chung của AURA (sự kiện, đấu giá, hệ số...) cho mọi người chơi
--   PvpUpdate(pvpState)     : trạng thái đấu trường của riêng người chơi (Types.PvpState)
-- Client -> Server (không trả về)
--   PvpAttack()             : đánh đối thủ trong trận PvP (server tự biết mục tiêu)
local EVENTS = {
	"StateUpdate",
	"Notify",
	"OpenShop",
	"OpenLeaderboard",
	"OpenAura",
	"AuraUpdate",
	"PvpUpdate",
	"PvpAttack",
}

-- Client -> Server (có trả về)
--   GetState()                    -> snapshot
--   ShopBuy(shopId, itemId)       -> ok: boolean, message: string
--   GetLeaderboard()              -> Types.LeaderboardView (nil nếu bị rate-limit)
--   GetAuraState()                -> Types.AuraView (nil nếu bị rate-limit)
--   AssetLease(assetId)           -> ok: boolean, message: string
--   AssetReturn(assetId)          -> ok: boolean, message: string
--   AuctionBid(amount)            -> ok: boolean, message: string
--   GetProfile()                  -> Types.ProfileView của chính người gọi (nil nếu bị rate-limit)
--   EquipCosmetic(id)             -> ok, message ("" = bỏ bảng tên màu)
--   EquipTitle(title)             -> ok, message ("" = gỡ danh hiệu)
local FUNCTIONS = {
	"GetState",
	"ShopBuy",
	"GetLeaderboard",
	"GetAuraState",
	"AssetLease",
	"AssetReturn",
	"AuctionBid",
	"GetProfile",
	"EquipCosmetic",
	"EquipTitle",
}

local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	assert(folder, "Không tìm thấy thư mục Remotes trong ReplicatedStorage")
	return folder :: Folder
end

local function ensure(folder: Folder, className: string, name: string)
	if not folder:FindFirstChild(name) then
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
end

-- Chỉ gọi trên server
function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init chỉ được gọi trên server")
	local folder = getFolder()
	for _, name in EVENTS do
		ensure(folder, "RemoteEvent", name)
	end
	for _, name in FUNCTIONS do
		ensure(folder, "RemoteFunction", name)
	end
end

function Remotes.Event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "RemoteEvent không tồn tại: " .. name)
	local remote = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	assert(remote and remote:IsA("RemoteEvent"), "Thiếu RemoteEvent: " .. name)
	return remote
end

function Remotes.Function(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), "RemoteFunction không tồn tại: " .. name)
	local remote = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	assert(remote and remote:IsA("RemoteFunction"), "Thiếu RemoteFunction: " .. name)
	return remote
end

return Remotes
