--!strict
--[[
	CosmeticService — cosmetic CHỈ TRANG TRÍ: bảng tên màu (bán bằng Game Pass) và gắn danh hiệu.

	  * Quyền sở hữu Game Pass do Roblox quản: kiểm tra bằng MarketplaceService:UserOwnsGamePassAsync khi
	    vào game và cập nhật ngay khi mua xong (PromptGamePassPurchaseFinished). Không lưu quyền sở hữu
	    trong dữ liệu, không xử lý receipt, không bao giờ cho tiền / chỉ số / XP / Nổi tiếng.
	  * Lựa chọn đang dùng (data.Cosmetics) được giữ qua các mùa (Config.Season.Persistent).
	  * Danh hiệu gắn được phải nằm trong data.Titles (do server trao cuối mùa); gắn miễn phí.
	  * Remote EquipCosmetic(id) / EquipTitle(title): kiểm tra kiểu + độ dài, rate-limit, pcall; chuỗi rỗng
	    nghĩa là gỡ. Không gắn với vật thể trong map nên không kiểm tra khoảng cách.
	  * Bảng tên trên đầu nhân vật do Util/NameTag dựng lại mỗi khi hồi sinh hoặc đổi lựa chọn.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local NameTag = require(script.Parent.Parent.Util.NameTag)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validate = require(script.Parent.Parent.Util.Validate)

local EquipCosmetic = Remotes.Function("EquipCosmetic")
local EquipTitle = Remotes.Function("EquipTitle")

local services: Types.Services = {}
-- Món người chơi sở hữu (theo Game Pass); bảng yếu để người rời game tự được dọn
local owned: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local equipLimiter =
	RateLimiter.new(Config.RateLimits.EquipCosmetic.Calls, Config.RateLimits.EquipCosmetic.Window)
local titleLimiter =
	RateLimiter.new(Config.RateLimits.EquipTitle.Calls, Config.RateLimits.EquipTitle.Window)

local CosmeticService = {}

function CosmeticService:Init(allServices: Types.Services)
	services = allServices
	for _, id in Config.Cosmetics.Order do
		if not Config.Cosmetics.Items[id] then
			warn(`[CosmeticService] Config.Cosmetics.Order có id không tồn tại: {id}`)
		end
	end
	for id, def in Config.Cosmetics.Items do
		if def.GamePassId < 0 or def.GamePassId % 1 ~= 0 then
			warn(`[CosmeticService] GamePassId của '{id}' không hợp lệ`)
		end
	end
end

function CosmeticService:Start()
	EquipCosmetic.OnServerInvoke = function(player: Player, id: any)
		return self:_handle(player, id, equipLimiter, Config.Cosmetics.MaxIdLength, function(value)
			return self:Equip(player, value)
		end)
	end
	EquipTitle.OnServerInvoke = function(player: Player, title: any)
		return self:_handle(
			player,
			title,
			titleLimiter,
			Config.Cosmetics.MaxTitleLength,
			function(value)
				return self:EquipTitle(player, value)
			end
		)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if purchased then
				self:_onPassPurchased(player, passId)
			end
		end
	)

	services.Data:OnLoaded(function(player: Player)
		self:RefreshOwnership(player)
		self:ApplyTag(player)
	end)

	-- Dựng bảng tên khi nhân vật xuất hiện VÀ mỗi khi có phần đầu mới: Roblox thay các phần cơ thể
	-- khi tải xong ngoại hình avatar, làm bảng tên gắn trên đầu cũ bị xoá theo.
	local function hook(player: Player, character: Model)
		character.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Head" and player.Character == character then
				self:ApplyTag(player)
			end
		end)
		self:ApplyTag(player) -- tự chờ đầu nhân vật nếu chưa có
	end
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			hook(player, character)
		end)
		local character = player.Character
		if character then
			hook(player, character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

-- ───────────────────────────── API công khai ─────────────────────────────

function CosmeticService:IsOwned(player: Player, id: string): boolean
	local set = owned[player]
	return set ~= nil and set[id] == true
end

-- Hỏi Roblox người chơi sở hữu Game Pass nào (yield). Lỗi mạng: giữ hiểu biết cũ cho món đó và không
-- gỡ món đang dùng (không phạt người chơi vì lỗi của dịch vụ).
function CosmeticService:RefreshOwnership(player: Player)
	local previous = owned[player] or {}
	local set: { [string]: boolean } = {}
	local failed: { [string]: boolean } = {}
	for id, def in Config.Cosmetics.Items do
		if def.GamePassId > 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.GamePassId)
			end)
			if ok then
				if result == true then
					set[id] = true
				end
			else
				failed[id] = true
				set[id] = previous[id]
				warn(
					`[CosmeticService] Không kiểm tra được Game Pass '{id}': {tostring(
						result
					)}`
				)
			end
		end
	end
	owned[player] = set

	-- Món đang dùng không còn sở hữu (ví dụ bị hoàn tiền): gỡ
	local data = services.Data:Get(player)
	if data then
		local equipped = data.Cosmetics.Equipped
		if equipped ~= "" and not set[equipped] and not failed[equipped] then
			data.Cosmetics.Equipped = ""
		end
	end
end

function CosmeticService:Equip(player: Player, id: string): (boolean, string)
	local data = services.Data:Get(player)
	if not data then
		return false, Config.Text.NoData
	end
	if id == "" then
		data.Cosmetics.Equipped = ""
		self:ApplyTag(player)
		return true, Config.Text.CosmeticUnequipped
	end
	local def = Config.Cosmetics.Items[id]
	if not def then
		return false, Config.Text.InvalidRequest
	end
	if not self:IsOwned(player, id) then
		return false, Config.Text.CosmeticNotOwned
	end
	data.Cosmetics.Equipped = id
	self:ApplyTag(player)
	return true, string.format(Config.Text.CosmeticEquipped, def.Name)
end

function CosmeticService:EquipTitle(player: Player, title: string): (boolean, string)
	local data = services.Data:Get(player)
	if not data then
		return false, Config.Text.NoData
	end
	if title == "" then
		data.Cosmetics.Title = ""
		self:ApplyTag(player)
		return true, Config.Text.TitleUnequipped
	end
	if not table.find(data.Titles, title) then
		return false, Config.Text.TitleNotOwned
	end
	data.Cosmetics.Title = title
	self:ApplyTag(player)
	return true, string.format(Config.Text.TitleEquipped, title)
end

-- Danh sách cosmetic cho cửa sổ Hồ sơ
function CosmeticService:GetViews(player: Player): { Types.CosmeticView }
	local data = services.Data:Get(player)
	local equipped = if data then data.Cosmetics.Equipped else ""
	local views: { Types.CosmeticView } = {}
	for _, id in Config.Cosmetics.Order do
		local def = Config.Cosmetics.Items[id]
		if def then
			table.insert(views, {
				Id = id,
				Name = def.Name,
				Owned = self:IsOwned(player, id),
				Equipped = equipped == id,
				GamePassId = def.GamePassId,
			})
		end
	end
	return views
end

-- Dựng / cập nhật bảng tên trên nhân vật hiện tại của người chơi. Nhân vật chưa có đầu (đang dựng
-- avatar): chờ đầu ở luồng riêng rồi thử lại đúng một lần.
function CosmeticService:ApplyTag(player: Player, isRetry: boolean?)
	local data = services.Data:Get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local def = Config.Cosmetics.Items[data.Cosmetics.Equipped]
	local color = if def then def.Color else Config.Cosmetics.DefaultColor
	if NameTag.Apply(character, player.DisplayName, data.Cosmetics.Title, color) or isRetry then
		return
	end
	task.spawn(function()
		character:WaitForChild("Head", 10)
		if player.Character == character then
			self:ApplyTag(player, true)
		end
	end)
end

-- ───────────────────────────── Nội bộ ─────────────────────────────

function CosmeticService:_onPassPurchased(player: Player, passId: number)
	for id, def in Config.Cosmetics.Items do
		if def.GamePassId > 0 and def.GamePassId == passId then
			local set = owned[player] or {}
			set[id] = true
			owned[player] = set
			services.Replication:Notify(
				player,
				string.format(Config.Text.CosmeticPurchased, def.Name),
				"success"
			)
		end
	end
end

-- Khung chung cho handler Remote: kiểu, độ dài, rate-limit, pcall
function CosmeticService:_handle(
	player: Player,
	value: any,
	limiter: RateLimiter.RateLimiter,
	maxLength: number,
	action: (value: string) -> (boolean, string)
): (boolean, string)
	if not Validate.isPlayer(player) then
		return false, Config.Text.InvalidRequest
	end
	if not limiter:Allow(player) then
		return false, Config.Text.TooFast
	end
	if type(value) ~= "string" or #value > maxLength then
		return false, Config.Text.InvalidRequest
	end
	local ok, success, message = pcall(action, value :: string)
	if not ok then
		warn(`[CosmeticService] Lỗi xử lý cosmetic: {tostring(success)}`)
		return false, Config.Text.ServerError
	end
	return success, message
end

return CosmeticService
