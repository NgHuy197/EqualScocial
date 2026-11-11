--!strict
--[[
	AssetRegistry.luau — registry TOÀN CẦU cho tài sản hiếm (Config.Assets[id].Stock).

	Một tài liệu duy nhất trong DataStore: { [assetId] = { [userId] = true } }. Số khoá của mỗi assetId
	là số tài sản đã bị giữ. Nhận / trả đều qua UpdateAsync nên hai server cùng nhận một lúc cũng
	không thể vượt kho.

	Studio không có DataStore (place chưa publish): dùng registry CỤC BỘ trong server (chỉ để test).
	Server thật mà DataStore lỗi: từ chối (không bao giờ tự rơi về registry cục bộ, vì sẽ cấp trùng
	giữa các server).

	Các hàm Count / TryClaim / Release có thể yield (gọi DataStore).
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

type Doc = { [string]: { [string]: boolean } }

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

local function countHolders(holders: { [string]: boolean }?): number
	local source: { [string]: boolean } = holders or {}
	local count = 0
	for _ in source do
		count += 1
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
	return countHolders(doc[assetId])
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
		local holders = doc[assetId] or {}
		if holders[key] then
			alreadyHeld = true -- đã giữ rồi: coi như thành công, không ghi lại
			return nil
		end
		if countHolders(holders) >= stock then
			soldOut = true
			return nil
		end
		holders[key] = true
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

-- Trả một tài sản hiếm về kho
function AssetRegistry.Release(self: AssetRegistry, assetId: string, userId: number): boolean
	local key = tostring(userId)
	local wrote = self:_update(function(doc: Doc): Doc?
		local holders = doc[assetId]
		if not holders or not holders[key] then
			return nil
		end
		holders[key] = nil
		return doc
	end)
	return wrote
end

return AssetRegistry
