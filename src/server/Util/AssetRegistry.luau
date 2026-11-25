--!strict
--[[
	AssetRegistry.luau — registry TOÀN CẦU cho tài sản hiếm (Config.Assets[id].Stock).

	Một tài liệu duy nhất trong DataStore: { [assetId] = { [userId] = thời điểm nhịp gần nhất (os.time) } }.
	Nhận / trả / nhịp đều qua UpdateAsync nên hai server cùng nhận một lúc cũng không thể vượt kho.

	Chủ vắng mặt: chủ đang online gửi "nhịp" (Touch) mỗi chu kỳ AURA và lúc vào game. Chủ không có nhịp
	quá Config.AssetRegistry.IdleSeconds thì KHÔNG được tính là đang giữ (Count / Remaining bỏ qua),
	và bị gỡ khỏi registry khi có người nhận suất đó (TryClaim). Khi người đó quay lại, Touch trả về
	"evicted" để AssetService thu hồi tài sản trong dữ liệu của họ. Giá trị cũ `true` (trước khi có
	nhịp) được coi là đang hoạt động.

	Studio không có DataStore (place chưa publish): dùng registry CỤC BỘ trong server (chỉ để test).
	Server thật mà DataStore lỗi: từ chối (không bao giờ tự rơi về registry cục bộ, vì sẽ cấp trùng
	giữa các server).

	Các hàm Count / TryClaim / Release có thể yield (gọi DataStore).
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

type Doc = { [string]: { [string]: any } } -- userId -> os.time() nhịp gần nhất (hoặc true: dữ liệu cũ)

type Fields = {
	Store: DataStore?,
	LocalDoc: Doc,
	AllowLocal: boolean, -- chỉ Studio mới được dùng registry cục bộ
	WarnedLocal: boolean,
	CacheDoc: Doc?,
	CacheAt: number,
}

local AssetRegistry = {}
AssetRegistry.__index = AssetRegistry

export type AssetRegistry = typeof(setmetatable({} :: Fields, AssetRegistry))

local function deepCopyDoc(doc: Doc): Doc
	local copy: Doc = {}
	for assetId, holders in doc do
		copy[assetId] = table.clone(holders)
	end
	return copy
end

-- Chủ còn được tính là đang giữ: có nhịp trong IdleSeconds gần đây (giá trị cũ `true` luôn tính)
local function isActive(value: any, now: number): boolean
	if type(value) == "number" then
		return now - value <= Config.AssetRegistry.IdleSeconds
	end
	return value ~= nil
end

-- Số chủ đang hoạt động
local function countHolders(holders: { [string]: any }?, now: number): number
	local source: { [string]: any } = holders or {}
	local count = 0
	for _, value in source do
		if isActive(value, now) then
			count += 1
		end
	end
	return count
end

function AssetRegistry.new(): AssetRegistry
	return setmetatable({
		Store = nil,
		LocalDoc = {},
		AllowLocal = RunService:IsStudio(),
		WarnedLocal = false,
		CacheDoc = nil,
		CacheAt = 0,
	}, AssetRegistry)
end

-- GetDataStore ném lỗi ngay khi place chưa publish: bọc pcall, Store = nil nghĩa là dùng chế độ cục bộ
function AssetRegistry.Init(self: AssetRegistry)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.AssetRegistry.StoreName)
	end)
	if ok then
		self.Store = result
	else
		self.Store = nil
		self:_warnLocal(result)
	end
end

function AssetRegistry._warnLocal(self: AssetRegistry, err: any)
	if not self.WarnedLocal then
		self.WarnedLocal = true
		if self.AllowLocal then
			warn(
				`[AssetRegistry] DataStore không khả dụng, dùng registry cục bộ: {tostring(
					err
				)}`
			)
		else
			warn(
				`[AssetRegistry] DataStore không khả dụng và đây là server thật, từ chối nhận/trả: {tostring(
					err
				)}`
			)
		end
	end
end

-- true nếu đang dùng registry cục bộ (kho chỉ tính trong server này)
function AssetRegistry.IsLocal(self: AssetRegistry): boolean
	return self.Store == nil and self.AllowLocal
end

-- Đọc tài liệu (có đệm). nil nếu không đọc được và không được phép dùng cục bộ.
function AssetRegistry._read(self: AssetRegistry): Doc?
	local store = self.Store
	if not store then
		return if self.AllowLocal then self.LocalDoc else nil
	end
	local cached = self.CacheDoc
	if cached and os.clock() - self.CacheAt < Config.AssetRegistry.CacheSeconds then
		return cached
	end
	local ok, result = pcall(function()
		return store:GetAsync(Config.AssetRegistry.Key)
	end)
	if not ok then
		self:_warnLocal(result)
		return nil
	end
	local doc: Doc = if type(result) == "table" then result :: Doc else {}
	self.CacheDoc = doc
	self.CacheAt = os.clock()
	return doc
end

-- Số tài sản `assetId` đã bị giữ; nil nếu không biết (server thật mà DataStore lỗi)
function AssetRegistry.Count(self: AssetRegistry, assetId: string): number?
	local doc = self:_read()
	if not doc then
		return nil
	end
	return countHolders(doc[assetId], os.time())
end

-- Số còn lại theo kho Config; nil nếu không biết
function AssetRegistry.Remaining(self: AssetRegistry, assetId: string): number?
	local def = Config.Assets[assetId]
	local count = self:Count(assetId)
	if not def or not def.Stock or count == nil then
		return nil
	end
	return math.max(0, def.Stock - count)
end

-- Áp một phép biến đổi lên tài liệu. transform trả về nil nghĩa là huỷ (không ghi).
-- Trả về (đã ghi, lý do lỗi nếu có).
function AssetRegistry._update(
	self: AssetRegistry,
	transform: (doc: Doc) -> Doc?
): (boolean, string?)
	local store = self.Store
	if not store then
		if not self.AllowLocal then
			return false, "unavailable"
		end
		local result = transform(deepCopyDoc(self.LocalDoc))
		if result then
			self.LocalDoc = result
			return true, nil
		end
		return false, nil
	end

	local wrote = false
	local ok, err = pcall(function()
		store:UpdateAsync(Config.AssetRegistry.Key, function(old: any)
			local doc: Doc = if type(old) == "table" then old :: Doc else {}
			local result = transform(doc)
			wrote = result ~= nil
			return result -- nil: UpdateAsync huỷ, không ghi
		end)
	end)
	self.CacheDoc = nil -- buộc đọc lại lần sau
	if not ok then
		self:_warnLocal(err)
		return false, "unavailable"
	end
	return wrote, nil
end

-- Nhận một tài sản hiếm cho người chơi (nguyên tử). Trả về (thành công, lý do: "sold_out" | "unavailable")
function AssetRegistry.TryClaim(
	self: AssetRegistry,
	assetId: string,
	userId: number
): (boolean, string?)
	local def = Config.Assets[assetId]
	if not def or not def.Stock then
		return false, "unavailable"
	end
	local stock = def.Stock
	local key = tostring(userId)
	local soldOut = false
	local alreadyHeld = false

	local wrote, reason = self:_update(function(doc: Doc): Doc?
		local now = os.time()
		local holders: { [string]: any } = doc[assetId] or {}
		if holders[key] ~= nil then
			alreadyHeld = true -- đã giữ rồi: coi như thành công, không ghi lại
			return nil
		end
		if countHolders(holders, now) >= stock then
			soldOut = true
			return nil
		end
		-- Gỡ chủ vắng mặt quá lâu để nhường suất (họ sẽ bị thu hồi khi quay lại)
		for holder, value in table.clone(holders) do
			if not isActive(value, now) then
				holders[holder] = nil
			end
		end
		holders[key] = now
		doc[assetId] = holders
		return doc
	end)
	if wrote or alreadyHeld then
		return true, nil
	end
	if reason then
		return false, reason
	end
	return false, if soldOut then "sold_out" else "unavailable"
end

-- Nhịp của chủ đang online: ghi lại thời điểm hoạt động. Trả về "ok", "evicted" (suất đã bị gỡ vì
-- vắng mặt quá lâu và đã có người khác nhận) hoặc "unavailable" (không đọc/ghi được registry).
function AssetRegistry.Touch(self: AssetRegistry, assetId: string, userId: number): string
	local key = tostring(userId)
	local evicted = false
	local wrote, reason = self:_update(function(doc: Doc): Doc?
		local holders = doc[assetId]
		if not holders or holders[key] == nil then
			evicted = true
			return nil
		end
		holders[key] = os.time()
		return doc
	end)
	if evicted then
		return "evicted"
	end
	if wrote then
		return "ok"
	end
	return if reason then "unavailable" else "ok"
end

-- Trả một tài sản hiếm về kho
function AssetRegistry.Release(self: AssetRegistry, assetId: string, userId: number): boolean
	local key = tostring(userId)
	local wrote = self:_update(function(doc: Doc): Doc?
		local holders = doc[assetId]
		if not holders or holders[key] == nil then
			return nil
		end
		holders[key] = nil
		return doc
	end)
	return wrote
end

return AssetRegistry
