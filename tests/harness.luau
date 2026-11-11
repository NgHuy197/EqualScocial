-- Harness chạy các module THẬT của dự án trên Luau CLI với môi trường Roblox giả lập.
-- Không chạy trực tiếp file này: tests/build_tests.py chèn bảng SOURCES (đường dẫn -> mã nguồn) lên đầu.
-- Mỗi mục "═══ N. ..." là một nhóm kiểm tra; kết thúc in "KẾT QUẢ: x đạt, y lỗi" và lỗi nếu y > 0.

local passed, failed = 0, 0
local function check(name, cond, extra)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (extra and (" -> " .. tostring(extra)) or ""))
	end
end
local function eq(name, got, expected)
	check(name, got == expected, "got " .. tostring(got) .. ", expected " .. tostring(expected))
end
local function near(name, got, expected)
	check(name, type(got) == "number" and math.abs(got - expected) < 1e-6, "got " .. tostring(got) .. ", expected " .. tostring(expected))
end

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in v do c[k] = deepCopy(x) end
	return c
end

-- ─── Stub kiểu dữ liệu Roblox ───
local Vector3 = {}
local V3Meta = {}
V3Meta.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	return nil
end
V3Meta.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3Meta.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3Meta.__div = function(a, k) return Vector3.new(a.X / k, a.Y / k, a.Z / k) end
V3Meta.__mul = function(a, k) return Vector3.new(a.X * k, a.Y * k, a.Z * k) end
function Vector3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3Meta) end
local Color3 = { fromRGB = function() return {} end, new = function() return {} end }
local Enum = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return {} end }) end })
-- Instance.new chỉ cần trả bảng thuần (CombatService tạo Folder "Monsters"); dựng UI thật không chạy ở đây
local Instance = { new = function(className) return { ClassName = className, Destroy = function() end } end }
local CFrame = { new = function(position) return { Position = position } end }

local function typeofStub(v)
	if type(v) == "table" and rawget(v, "_isInstance") then return "Instance" end
	return type(v)
end

local warnings = {}
local function warnStub(...)
	local parts = {}
	for _, v in { ... } do table.insert(parts, tostring(v)) end
	table.insert(warnings, table.concat(parts, " "))
end

local task = {
	spawn = function(f, ...)
		if type(f) == "function" then
			local ok, err = pcall(f, ...)
			if not ok then print("task.spawn lỗi: " .. tostring(err)) failed += 1 end
		end
	end,
	delay = function() end,
	wait = function() return 0 end,
}
task.defer = task.spawn

local function newSignal()
	local handlers = {}
	return {
		Connect = function(_, fn) table.insert(handlers, fn) return { Disconnect = function() end } end,
		Fire = function(_, ...) for _, h in handlers do h(...) end end,
	}
end

-- ─── Cây module giả (script.Parent..., ReplicatedStorage.Shared...) ───
local nodes = {}
local nodeMeta = { __index = function(t, k) return rawget(t, "_children")[k] end }
local function ensureNode(path)
	if nodes[path] then return nodes[path] end
	local parentPath, name = string.match(path, "^(.*)/([^/]+)$")
	local node = setmetatable({ _path = path, _name = name or path, _children = {} }, nodeMeta)
	nodes[path] = node
	if parentPath then
		local parent = ensureNode(parentPath)
		node.Parent = parent
		parent._children[node._name] = node
	end
	return node
end
for path in SOURCES do ensureNode(path) end
-- ProfileStore (Vendor) không được ghép vào SOURCES: chỉ cần node để fakeRequire trả bản giả
ensureNode("server/Vendor/ProfileStore")

-- ─── Dịch vụ Roblox giả ───
local isStudio = true
local storeFail = false
local storeData = {}
local fired = {} -- { name, player, args }

local serverTime = 0 -- giờ server giả lập (đổi để thử ngày trong tuần)
local nameLookup = {} -- userId -> tên (không có = GetNameFromUserIdAsync ném lỗi)

local PlayersService = { _list = {}, PlayerAdded = newSignal(), PlayerRemoving = newSignal() }
function PlayersService:GetPlayers() return self._list end
function PlayersService:GetNameFromUserIdAsync(userId)
	local name = nameLookup[userId]
	if not name then error("không tìm thấy người dùng " .. tostring(userId)) end
	return name
end

local fakeStore = {
	GetAsync = function(_, key)
		if storeFail then error("StudioAccessToApisNotAllowed") end
		return deepCopy(storeData[key])
	end,
	UpdateAsync = function(_, key, fn)
		if storeFail then error("API down") end
		local result = fn(deepCopy(storeData[key]))
		if result ~= nil then storeData[key] = deepCopy(result) end
		return deepCopy(storeData[key])
	end,
}


-- ProfileStore giả: dữ liệu thô nằm ở storeData[key] (giống bản cũ để các test lưu/tải giữ nguyên),
-- khóa phiên ở psLocks[key] = JobId của server đang giữ. storeFail + Studio => kho giả (NoAccess),
-- storeFail + server thật => StartSessionAsync trả nil (hết thời gian chờ).
local psLocks, psMock, psActive = {}, {}, {}
local psNewFail = false
local psUserIds = {}
local FakeProfileStore = { DataStoreState = "NotReady", Constants = {} }
function FakeProfileStore.SetConstant(name, value) FakeProfileStore.Constants[name] = value end
function FakeProfileStore.New(name, template)
	if psNewFail then error("ProfileStore.New lỗi giả lập") end
	local storeObj = { Name = name }
	function storeObj:StartSessionAsync(key, params)
		if psActive[key] then error("Profile " .. key .. " is already loaded in this session") end
		local noAccess = storeFail and isStudio
		if storeFail and not isStudio then return nil end
		FakeProfileStore.DataStoreState = if noAccess then "NoAccess" else "Access"
		if params and params.Cancel and params.Cancel() then return nil end
		local backing = if noAccess then psMock else storeData
		local locks = if noAccess then {} else psLocks
		if locks[key] ~= nil and locks[key] ~= "test" then return nil end -- server khác giữ khóa
		locks[key] = "test"
		local raw = backing[key]
		local profile = { Key = key, Data = if raw ~= nil then deepCopy(raw) else deepCopy(template), _active = true }
		profile.OnSessionEnd = newSignal()
		function profile:AddUserId(id) psUserIds[key] = id end
		function profile:IsActive() return self._active end
		local function finish(save)
			if not profile._active then return end
			profile._active = false
			if save then backing[key] = deepCopy(profile.Data) end
			locks[key] = nil
			psActive[key] = nil
			profile.OnSessionEnd:Fire()
		end
		function profile:EndSession() finish(true) end
		profile._steal = function() -- server khác giành phiên: bản này không được lưu nữa
			profile._active = false
			psLocks[key] = "other-server"
			psActive[key] = nil
			profile.OnSessionEnd:Fire()
		end
		psActive[key] = profile
		return profile
	end
	return storeObj
end

-- OrderedDataStore giả: lưu key -> số, GetSortedAsync trả trang giảm dần
local orderedData = {}
local orderedFail = false
local orderedStore = {
	SetAsync = function(_, key, value)
		if orderedFail then error("API down") end
		assert(type(value) == "number" and value >= 0 and value % 1 == 0, "OrderedDataStore chỉ nhận số nguyên không âm")
		orderedData[key] = value
	end,
	GetSortedAsync = function(_, ascending, pageSize)
		if orderedFail then error("API down") end
		local list = {}
		for key, value in orderedData do table.insert(list, { key = key, value = value }) end
		table.sort(list, function(a, b) return a.value > b.value end)
		local page = {}
		for i = 1, math.min(#list, pageSize) do page[i] = list[i] end
		return { GetCurrentPage = function() return page end }
	end,
}
local orderedUnavailable = true -- true: GetOrderedDataStore ném lỗi (giống place chưa publish)

local taggedInstances = {}
local fakeServices = {
	Players = PlayersService,
	ReplicatedStorage = { Shared = nodes["shared"] },
	RunService = { IsStudio = function() return isStudio end },
	DataStoreService = {
		GetDataStore = function() return fakeStore end,
		GetOrderedDataStore = function()
			if orderedUnavailable then error("You must publish this place to the web to access DataStore.") end
			return orderedStore
		end,
	},
	CollectionService = {
		GetTagged = function(_, tag) return taggedInstances[tag] or {} end,
		AddTag = function() end,
		GetInstanceAddedSignal = function() return newSignal() end,
		GetInstanceRemovedSignal = function() return newSignal() end,
	},
	Workspace = {
		GetServerTimeNow = function() return serverTime end,
		FindFirstChild = function() return nil end,
	},
}
local fakeGame = {
	GetService = function(_, name) return assert(fakeServices[name], "dịch vụ chưa giả lập: " .. name) end,
	BindToClose = function() end,
	JobId = "test",
}

local remoteFunctions = {}
local remoteEvents = {}
local RemotesStub = {
	Init = function() end,
	Event = function(name)
		if remoteEvents[name] then return remoteEvents[name] end
		remoteEvents[name] = {
			OnServerEvent = newSignal(),
			FireClient = function(_, player, ...) table.insert(fired, { name = name, player = player, args = { ... } }) end,
			FireAllClients = function(_, ...) table.insert(fired, { name = name, player = "*", args = { ... } }) end,
		}
		return remoteEvents[name]
	end,
	Function = function(name)
		remoteFunctions[name] = remoteFunctions[name] or {}
		return remoteFunctions[name]
	end,
}

-- Quái giả: ghi lại các lần dựng; thay cho Util/MonsterModel (dựng Instance thật, chạy trong Studio)
local built = {}
local MonsterModelStub = {
	Build = function(id, def, ground, parent)
		local model = { _isInstance = true, Destroyed = false, Name = def.Name }
		function model:Destroy() self.Destroyed = true end
		local handle = { Model = model, Body = { Position = ground + Vector3.new(0, def.Size.X / 2, 0) }, Fill = {} }
		table.insert(built, { Id = id, Handle = handle })
		return handle
	end,
	SetHealth = function(handle, fraction) handle.LastFraction = fraction end,
}
local boardWrites = {}
local BoardGuiStub = { Update = function(part, text) boardWrites[part] = text end }

local PRELUDE = "local game, script, require, task, typeof, warn, Vector3, Color3, Enum, Instance, CFrame = ...; "
local cache = {}
local fakeRequire
-- Nạp MỚI một module (bỏ qua cache) để thử các đường khởi tạo khác nhau của cùng một service
local function loadFresh(path)
	local chunk, err = loadstring(PRELUDE .. SOURCES[path], "=fresh/" .. path)
	assert(chunk, "không biên dịch được " .. path .. ": " .. tostring(err))
	return chunk(fakeGame, nodes[path], fakeRequire, task, typeofStub, warnStub, Vector3, Color3, Enum, Instance, CFrame)
end
fakeRequire = function(node)
	assert(type(node) == "table" and node._path, "require: module không hợp lệ")
	if node._path == "server/Vendor/ProfileStore" then return FakeProfileStore end
	assert(SOURCES[node._path], "require: module không hợp lệ")
	local path = node._path
	if path == "server/Vendor/ProfileStore" then return FakeProfileStore end
	if cache[path] == nil then
		if path == "shared/Remotes" then
			cache[path] = RemotesStub
		elseif path == "server/Util/MonsterModel" then
			cache[path] = MonsterModelStub
		elseif path == "server/Util/BoardGui" then
			cache[path] = BoardGuiStub
		else
			cache[path] = loadFresh(path)
		end
	end
	return cache[path]
end

-- ─── Người chơi giả ───
local nextId = 100
local function newPlayer(userId, name, pos)
	nextId += 1
	local humanoid = { Health = 100, Died = newSignal(), IsA = function(_, c) return c == "Humanoid" end }
	function humanoid:TakeDamage(amount) self.Health = math.max(0, self.Health - amount) end
	local rootPart = { Position = pos or Vector3.new(0, 0, 0), IsA = function(_, c) return c == "BasePart" end }
	local character = {
		_pivots = {},
		FindFirstChildOfClass = function(_, cls) if cls == "Humanoid" then return humanoid end return nil end,
		FindFirstChild = function(_, n) if n == "HumanoidRootPart" then return rootPart end return nil end,
		WaitForChild = function(_, n)
			if n == "Humanoid" then return humanoid end
			if n == "HumanoidRootPart" then return rootPart end
			return nil
		end,
	}
	function character:PivotTo(cframe) table.insert(self._pivots, cframe) end
	local player = {
		Name = name or ("P" .. nextId), DisplayName = name or ("P" .. nextId), UserId = userId or nextId, Parent = PlayersService,
		Character = character, _isInstance = true, _loadCount = 0, _kicked = nil,
		IsA = function(_, c) return c == "Player" end,
		CharacterAdded = newSignal(),
	}
	player.LoadCharacterAsync = function(self) self._loadCount += 1 end
	player.Kick = function(self, msg) self._kicked = msg end
	table.insert(PlayersService._list, player)
	return player, rootPart, humanoid
end

local function notifications(player)
	local out = {}
	for _, f in fired do
		if f.name == "Notify" and f.player == player then table.insert(out, { text = f.args[1], kind = f.args[2] }) end
	end
	return out
end
local function lastNotification(player)
	local list = notifications(player)
	return list[#list]
end

-- ═══════════════ Nạp module và khởi tạo ═══════════════
local Config = fakeRequire(nodes["shared/Config"])
local Format = fakeRequire(nodes["shared/Format"])

local ORDER = { "Data", "Economy", "Stats", "Skills", "Jobs", "Stations", "Shop", "School", "Combat", "Assets", "Auction", "Aura", "Season", "Pvp", "Leaderboard", "Replication" }
local MODULE_OF = {
	Data = "DataService", Economy = "EconomyService", Stats = "StatsService", Skills = "SkillService",
	Jobs = "JobService", Stations = "StationService", Shop = "ShopService", School = "SchoolService",
	Combat = "CombatService", Leaderboard = "LeaderboardService", Replication = "ReplicationService",
	Assets = "AssetService", Auction = "AuctionService", Aura = "AuraService",
	Season = "SeasonService", Pvp = "PvpService",
}
local svc = {}
for _, n in ORDER do svc[n] = fakeRequire(nodes["server/Services/" .. MODULE_OF[n]]) end
for _, n in ORDER do svc[n]:Init(svc) end
-- Cảnh báo duy nhất được phép: DataStore xếp hạng không khả dụng (giả lập Studio chưa publish)
local unexpected = {}
for _, w in warnings do
	if not string.find(w, "DataStore xếp hạng", 1, true) then table.insert(unexpected, w) end
end
eq("Init không sinh cảnh báo cấu hình", #unexpected, 0)
if #unexpected > 0 then print(table.concat(unexpected, "\n")) end

-- ═══════════════ 1. Format ═══════════════
eq("Format.number 1250", Format.number(1250), "1.250")
eq("Format.number 100", Format.number(100), "100")
eq("Format.number 1000000", Format.number(1000000), "1.000.000")
eq("Format.number 999999999999", Format.number(999999999999), "999.999.999.999")
eq("Format.money 0", Format.money(0), "$0")
eq("Format.money -5", Format.money(-5), "-$5")

-- ═══════════════ 2. Tải dữ liệu người chơi mới ═══════════════
local A, rootA = newPlayer(1, "Alice")
svc.Data:_load(A)
local dA = svc.Data:Get(A)
check("Alice có dữ liệu", dA ~= nil)
eq("Tiền khởi điểm", dA.Money, 100)
for statId, v in Config.Stats.Start do eq("Chỉ số khởi điểm " .. statId, dA.Stats[statId], v) end
eq("Skill Strength Lv0", dA.Skills.Strength.Level, 0)
eq("Skill Communication Lv0", dA.Skills.Communication.Level, 0)
check("Owned rỗng", next(dA.Owned) == nil)

-- ═══════════════ 3. Economy ═══════════════
eq("Add +12", svc.Economy:Add(A, 12, "job"), 12)
eq("Số dư 112", svc.Economy:Get(A), 112)
eq("Add số âm bị từ chối", svc.Economy:Add(A, -5, "job"), 0)
eq("Add NaN bị từ chối", svc.Economy:Add(A, 0 / 0, "job"), 0)
eq("Add inf bị từ chối", svc.Economy:Add(A, math.huge, "job"), 0)
eq("Add thiếu reason bị từ chối", svc.Economy:Add(A, 5, nil), 0)
eq("Add số lẻ làm tròn xuống", svc.Economy:Add(A, 2.9, "job"), 2)
eq("Số dư 114", svc.Economy:Get(A), 114)
eq("TrySpend quá số dư", svc.Economy:TrySpend(A, 500, "shop"), false)
eq("Số dư không đổi khi thất bại", svc.Economy:Get(A), 114)
eq("TrySpend 14", svc.Economy:TrySpend(A, 14, "shop"), true)
eq("Số dư 100", svc.Economy:Get(A), 100)
eq("TrySpend số âm bị từ chối", svc.Economy:TrySpend(A, -1, "shop"), false)
eq("TakePercent 10% của 100", svc.Economy:TakePercent(A, 0.1, "tax"), 10)
eq("Số dư 90", svc.Economy:Get(A), 90)
eq("TakePercent 0 bị từ chối", svc.Economy:TakePercent(A, 0, "tax"), 0)
local seen = {}
svc.Economy:OnTransaction(function(t) table.insert(seen, t) end)
svc.Economy:Add(A, 10, "job")
eq("OnTransaction nhận giao dịch", #seen, 1)
eq("Giao dịch có reason", seen[1].Reason, "job")
eq("Giao dịch có delta", seen[1].Delta, 10)
svc.Economy:TrySpend(A, 10, "shop") -- về lại 90
dA.Money = Config.Economy.MaxMoney - 5
eq("Add bị chặn ở MaxMoney", svc.Economy:Add(A, 100, "job"), 5)
dA.Money = 90

-- ═══════════════ 4. Nghề, XP, lên cấp ═══════════════
local wh = Config.Jobs.warehouse
svc.Jobs:_work(A, wh)
eq("Làm kho: tiền 102", dA.Money, 102)
near("Năng lượng 94", dA.Stats.Energy, 94)
near("Độ no 96", dA.Stats.Hunger, 96)
near("Sạch sẽ 95", dA.Stats.Hygiene, 95)
near("Căng thẳng 13", dA.Stats.Stress, 13)
eq("XP Strength 10", dA.Skills.Strength.XP, 10)
eq("Thông báo công việc", lastNotification(A).text, "Bốc vác kho hàng: +$12 · +10 XP Sức mạnh")
for _ = 1, 4 do svc.Jobs:_work(A, wh) end
eq("Sau 5 lượt: Strength Lv1", dA.Skills.Strength.Level, 1)
eq("Sau lên cấp XP dư 0", dA.Skills.Strength.XP, 0)
local sawLevelUp = false
for _, n in notifications(A) do if n.text == "Kỹ năng Sức mạnh đã lên cấp 1!" and n.kind == "levelup" then sawLevelUp = true end end
check("Có thông báo lên cấp", sawLevelUp)
local before = dA.Money
svc.Jobs:_work(A, wh)
eq("Lương Lv1 = round(12*1.1) = 13", dA.Money - before, 13)
local bar = Config.Jobs.barista
before = dA.Money
svc.Jobs:_work(A, bar)
eq("Pha chế Lv0 = $10", dA.Money - before, 10)
eq("XP Communication 10", dA.Skills.Communication.XP, 10)

-- Năng lượng thấp
dA.Stats.Energy = 14.9
before = dA.Money
local xpBefore = dA.Skills.Strength.XP
svc.Jobs:_work(A, wh)
eq("Quá mệt: không nhận tiền", dA.Money, before)
eq("Quá mệt: không nhận XP", dA.Skills.Strength.XP, xpBefore)
eq("Quá mệt: có cảnh báo", lastNotification(A).kind, "warning")
check("Cảnh báo ghi số 15", string.find(lastNotification(A).text, "15", 1, true) ~= nil, lastNotification(A).text)
dA.Stats.Energy = 15
before = dA.Money
svc.Jobs:_work(A, wh)
check("Đúng 15 Năng lượng thì được làm", dA.Money > before)

-- Lên tối đa
local gained = svc.Skills:AddXP(A, "Communication", 1e6)
check("Lên nhiều cấp một lúc", gained >= 19, gained)
eq("Giao tiếp đạt Lv20", dA.Skills.Communication.Level, 20)
eq("Tối đa thì XP về 0", dA.Skills.Communication.XP, 0)
near("Hệ số lương Lv20 = 3.0", svc.Skills:GetPayMultiplier(A, "Communication"), 3.0)
eq("Hết cấp không cộng nữa", svc.Skills:AddXP(A, "Communication", 100), 0)
eq("XPNeeded(0) = 50", svc.Skills:XPNeeded(0), 50)
eq("XPNeeded(19) = 525", svc.Skills:XPNeeded(19), 525)

-- ═══════════════ 5. Trạm ═══════════════
for k, v in Config.Stats.Start do dA.Stats[k] = v end
dA.Stats.Hygiene, dA.Stats.Energy, dA.Stats.Stress, dA.Stats.Happiness = 30, 30, 50, 50
local function useStation(player, id) svc.Stations:_use(player, id, Config.Stations[id]) end
local function expireStation(data, id) data.StationUsed[id] = os.time() - Config.Stations[id].Cooldown - 1 end
useStation(A, "shower")
near("Tắm +40 Sạch sẽ", dA.Stats.Hygiene, 70)
useStation(A, "bed")
near("Giường +40 Năng lượng", dA.Stats.Energy, 70)
near("Giường -10 Căng thẳng", dA.Stats.Stress, 40)
useStation(A, "bench")
near("Ghế -6 Căng thẳng", dA.Stats.Stress, 34)
near("Ghế +4 Hạnh phúc", dA.Stats.Happiness, 54)
-- Cooldown cân bằng theo từng người chơi
check("Ghi mốc dùng trạm", type(dA.StationUsed.shower) == "number")
check("Tắm xong: còn cooldown", svc.Stations:GetRemaining(A, "shower") > 0)
check("Cooldown tắm không quá cấu hình", svc.Stations:GetRemaining(A, "shower") <= Config.Stations.shower.Cooldown)
useStation(A, "shower")
near("Tắm lại khi còn cooldown: không có tác dụng", dA.Stats.Hygiene, 70)
check("Tắm lại khi còn cooldown: có cảnh báo", string.find(lastNotification(A).text, "cần chờ thêm", 1, true) ~= nil)
eq("Cảnh báo cooldown là loại warning", lastNotification(A).kind, "warning")
expireStation(dA, "shower")
eq("Hết cooldown: dùng được ngay", svc.Stations:GetRemaining(A, "shower"), 0)
useStation(A, "shower")
expireStation(dA, "shower")
useStation(A, "shower")
near("Sạch sẽ bị chặn ở 100", dA.Stats.Hygiene, 100)
check("Trạm khác không bị cooldown của tắm chặn", svc.Stations:GetRemaining(A, "bench") > 0 and svc.Stations:GetRemaining(A, "bed") > 0)
eq("Trạm không tồn tại: 0", svc.Stations:GetRemaining(A, "khong_co"), 0)
for id in Config.Stations do expireStation(dA, id) end

-- ═══════════════ 6. Công thức chỉ số theo thời gian ═══════════════
local function freshStats(overrides)
	local s = deepCopy(Config.Stats.Start)
	for k, v in overrides or {} do s[k] = v end
	return s
end
local s = freshStats()
svc.Stats:_applyTime(s, 1)
near("1 phút: Độ no -2", s.Hunger, 98)
near("1 phút: Năng lượng -1.5", s.Energy, 98.5)
near("1 phút: Sạch sẽ -1", s.Hygiene, 99)
near("1 phút ổn: Hạnh phúc +0.5", s.Happiness, 70.5)
near("1 phút ổn: Căng thẳng -0.5", s.Stress, 9.5)
near("1 phút ổn: Sức khỏe hồi (đã đầy)", s.Health, 100)

s = freshStats({ Health = 50 })
svc.Stats:_applyTime(s, 1)
near("Hồi sức khỏe +1/phút", s.Health, 51)

s = freshStats({ Hunger = 20 })
svc.Stats:_applyTime(s, 1) -- Độ no 18 < 30: một nhu cầu thấp
near("Một nhu cầu thấp: Hạnh phúc -1", s.Happiness, 69)
near("Một nhu cầu thấp: Căng thẳng +1", s.Stress, 11)
near("Có nhu cầu thấp: không hồi sức khỏe", s.Health, 100)

s = freshStats({ Hunger = 20, Energy = 20, Hygiene = 20 })
svc.Stats:_applyTime(s, 1)
near("Ba nhu cầu thấp: Hạnh phúc -3", s.Happiness, 67)
near("Ba nhu cầu thấp: Căng thẳng +3", s.Stress, 13)

s = freshStats({ Hunger = 0 })
svc.Stats:_applyTime(s, 1)
near("Đói: Sức khỏe -3", s.Health, 97)
near("Đói: Độ no giữ ở 0", s.Hunger, 0)

s = freshStats({ Hunger = 0, Energy = 0 })
svc.Stats:_applyTime(s, 1)
near("Đói + kiệt năng lượng chỉ trừ -3 một lần", s.Health, 97)

s = freshStats({ Stress = 95 })
svc.Stats:_applyTime(s, 1) -- Căng thẳng -0.5 -> 94.5 (>=90): -1, nhu cầu ổn: +1
near("Căng thẳng cao + nhu cầu ổn: -1 +1 = 0", s.Health, 100)

s = freshStats({ Stress = 95, Hunger = 20 })
svc.Stats:_applyTime(s, 1)
near("Căng thẳng cao + nhu cầu thấp: -1", s.Health, 99)

s = freshStats()
svc.Stats:_applyTime(s, 5)
near("5 phút: Độ no -10", s.Hunger, 90)
near("5 phút: Năng lượng -7.5", s.Energy, 92.5)

-- ═══════════════ 7. Kiệt sức ═══════════════
dA.Money = 1000
for k, v in Config.Stats.Start do dA.Stats[k] = v end
A._loadCount = 0
svc.Stats:Modify(A, { Health = -1000 })
eq("Kiệt sức: mất 10% tiền", dA.Money, 900)
for statId, v in Config.Stats.SafeReset do eq("Kiệt sức: reset " .. statId, dA.Stats[statId], v) end
eq("Kiệt sức: respawn một lần", A._loadCount, 1)
eq("Kiệt sức: thông báo", lastNotification(A).text, "Bạn đã kiệt sức và được đưa đi cấp cứu. Mất $100 (10% số tiền).")
eq("Kiệt sức: thông báo loại error", lastNotification(A).kind, "error")
svc.Stats:Modify(A, { Health = -5 })
eq("Modify chỉ số không hợp lệ không làm hỏng dữ liệu", svc.Stats:Modify(A, { NotAStat = 5, Hunger = 0 / 0 }), true)
near("Hunger không bị NaN", dA.Stats.Hunger, Config.Stats.SafeReset.Hunger)

-- ═══════════════ 8. Cửa hàng ═══════════════
local function fakeShop(shopId, pos)
	return {
		_isInstance = true, Position = pos,
		IsA = function(_, c) return c == "BasePart" end,
		IsDescendantOf = function() return true end,
		GetAttribute = function() return shopId end,
	}
end
taggedInstances[Config.Tags.Shop] = { fakeShop("restaurant", Vector3.new(5, 0, 0)), fakeShop("fashion", Vector3.new(5, 0, 30)) }

local B, rootB = newPlayer(2, "Bob", Vector3.new(0, 0, 0))
svc.Data:_load(B)
local dB = svc.Data:Get(B)
dB.Stats.Hunger = 50
local ok, msg = svc.Shop:_buy(B, "restaurant", "banh_mi")
eq("Mua bánh mì thành công", ok, true)
eq("Thông báo mua bánh mì", msg, "Đã mua Bánh mì (-$10).")
eq("Tiền sau bánh mì", dB.Money, 90)
near("Độ no +30", dB.Stats.Hunger, 80)
ok, msg = svc.Shop:_buy(B, "restaurant", "pho")
eq("Mua phở thành công", ok, true)
near("Phở: Độ no +60 (chặn 100)", dB.Stats.Hunger, 100)
near("Phở: Hạnh phúc +5", dB.Stats.Happiness, 75)
eq("Tiền sau phở", dB.Money, 65)
dB.Stats.Hunger, dB.Stats.Energy = 10, 10
svc.Shop:_buy(B, "restaurant", "nuoc_suoi")
near("Nước suối: Độ no +8", dB.Stats.Hunger, 18)
near("Nước suối: Năng lượng +5", dB.Stats.Energy, 15)
eq("Tiền sau nước suối", dB.Money, 60)

ok, msg = svc.Shop:_buy(B, "fashion", "sunglasses")
eq("Mua kính râm khi đứng xa bị từ chối", ok, false)
eq("Thông báo quá xa", msg, "Bạn đang đứng quá xa cửa hàng.")
eq("Tiền không đổi khi mua từ xa", dB.Money, 60)
rootB.Position = Vector3.new(5, 0, 28)
ok, msg = svc.Shop:_buy(B, "fashion", "sunglasses")
eq("Không đủ tiền", ok, false)
eq("Thông báo không đủ tiền", msg, "Bạn không đủ tiền.")
check("Chưa sở hữu kính râm", dB.Owned.sunglasses == nil)
dB.Money = 1000
ok, msg = svc.Shop:_buy(B, "fashion", "sunglasses")
eq("Mua kính râm thành công", ok, true)
eq("Tiền sau kính râm", dB.Money, 800)
eq("Nổi tiếng = 5", svc.Shop:GetFame(B), 5)
ok, msg = svc.Shop:_buy(B, "fashion", "sunglasses")
eq("Mua trùng bị từ chối", ok, false)
eq("Thông báo đã sở hữu", msg, "Bạn đã sở hữu món này rồi.")
eq("Mua trùng không trừ tiền", dB.Money, 800)
ok = svc.Shop:_buy(B, "fashion", "gold_watch")
eq("Mua đồng hồ vàng", ok, true)
eq("Nổi tiếng = 20", svc.Shop:GetFame(B), 20)
eq("Tiền sau đồng hồ", dB.Money, 200)
rootB.Position = Vector3.new(0, 0, 0)
ok, msg = svc.Shop:_buy(B, "fashion", "gold_watch")
eq("Mua trùng ở xa vẫn bị từ chối", ok, false)

-- Validate đầu vào của client
local C = newPlayer(3, "Carol", Vector3.new(0, 0, 0))
svc.Data:_load(C)
eq("shopId sai kiểu", select(2, svc.Shop:_handleBuy(C, 123, "banh_mi")), "Yêu cầu không hợp lệ.")
eq("itemId là bảng", select(2, svc.Shop:_handleBuy(C, "restaurant", {})), "Yêu cầu không hợp lệ.")
eq("id có ký tự lạ", select(2, svc.Shop:_handleBuy(C, "restaurant", "../x")), "Yêu cầu không hợp lệ.")
eq("id quá dài", select(2, svc.Shop:_handleBuy(C, "restaurant", string.rep("a", 64))), "Yêu cầu không hợp lệ.")
eq("shop không tồn tại", select(2, svc.Shop:_handleBuy(C, "casino", "banh_mi")), "Yêu cầu không hợp lệ.")
local D = newPlayer(4, "Dan", Vector3.new(0, 0, 0))
svc.Data:_load(D)
local limited = false
for _ = 1, 20 do
	local _, m = svc.Shop:_handleBuy(D, "restaurant", "nuoc_suoi")
	if m == "Bạn thao tác quá nhanh, hãy chậm lại một chút." then limited = true break end
end
check("Rate-limit ShopBuy chặn spam", limited)
check("Không phải Player bị từ chối", select(1, svc.Shop:_handleBuy({}, "restaurant", "banh_mi")) == false)
local E = newPlayer(5, "Eve", Vector3.new(0, 0, 0))
check("Chưa tải dữ liệu: bị từ chối", select(1, svc.Shop:_handleBuy(E, "restaurant", "banh_mi")) == false)

-- ═══════════════ 9. Snapshot ═══════════════
local snap1 = svc.Replication:BuildSnapshot(A)
local snap2 = svc.Replication:BuildSnapshot(A)
check("Seq tăng dần", snap2.Seq == snap1.Seq + 1)
eq("Snapshot có tiền", snap1.Money, dA.Money)
eq("Snapshot Strength level", snap1.Skills.Strength.Level, 1)
eq("Snapshot Strength Need = 75", snap1.Skills.Strength.Need, 75)
eq("Snapshot Communication tối đa Need = 0", snap1.Skills.Communication.Need, 0)
local snapB = svc.Replication:BuildSnapshot(B)
eq("Snapshot Nổi tiếng", snapB.Fame, 20)
eq("Snapshot đồ sở hữu", snapB.Owned.sunglasses, true)
check("Snapshot cho người chưa có dữ liệu là nil", svc.Replication:BuildSnapshot(E) == nil)
svc.Replication:Notify(A, "xin chào", "kind_la")
eq("Notify loại lạ về mặc định", lastNotification(A).kind, "info")

-- ═══════════════ 10. Lưu / tải / reconcile ═══════════════
dA.Money = 777
dA.Owned.sunglasses = true
dA.Skills.Strength.Level, dA.Skills.Strength.XP = 3, 12
dA.Stats.Hunger = 41
svc.Data:_release(A)
check("Sau khi rời, dữ liệu bị gỡ", svc.Data:Get(A) == nil)
check("Đã ghi DataStore", storeData["u_1"] ~= nil)
eq("Key lưu đúng định dạng", storeData["u_1"].Money, 777)

-- Làm dữ liệu cũ thiếu trường + có trường lạ để thử reconcile
storeData["u_1"].Skills.Communication = nil
storeData["u_1"].Stats.Health = nil
storeData["u_1"].Owned.fancy_future_item = true
local A2 = newPlayer(1, "Alice")
svc.Data:_load(A2)
local dA2 = svc.Data:Get(A2)
eq("Tải lại: tiền", dA2.Money, 777)
eq("Tải lại: đồ sở hữu", dA2.Owned.sunglasses, true)
eq("Tải lại: giữ trường lạ trong Owned", dA2.Owned.fancy_future_item, true)
eq("Tải lại: skill Strength", dA2.Skills.Strength.Level, 3)
eq("Tải lại: XP", dA2.Skills.Strength.XP, 12)
eq("Reconcile bổ sung skill thiếu", dA2.Skills.Communication.Level, Config.Skills.StartLevel)
eq("Reconcile bổ sung chỉ số thiếu", dA2.Stats.Health, Config.Stats.Start.Health)
eq("Tải lại: Độ no", dA2.Stats.Hunger, 41)

-- Dữ liệu hỏng
storeData["u_9"] = { Money = -50, Stats = { Hunger = 9999, Energy = "x" }, Skills = { Strength = { Level = 99, XP = -3 } } }
local F = newPlayer(9, "Fred")
svc.Data:_load(F)
local dF = svc.Data:Get(F)
eq("Dữ liệu hỏng: tiền âm về mặc định", dF.Money, 100)
eq("Dữ liệu hỏng: chỉ số vượt khoảng bị chặn", dF.Stats.Hunger, 100)
eq("Dữ liệu hỏng: chỉ số sai kiểu về mặc định", dF.Stats.Energy, Config.Stats.Start.Energy)
eq("Dữ liệu hỏng: level bị chặn ở tối đa", dF.Skills.Strength.Level, 20)
eq("Dữ liệu hỏng: XP âm về 0", dF.Skills.Strength.XP, 0)

-- ═══════════════ 11. Lỗi DataStore ═══════════════
storeFail, isStudio = true, true
local G = newPlayer(7, "Gina")
svc.Data:_load(G)
check("Studio không có API: vẫn có dữ liệu", svc.Data:Get(G) ~= nil)
check("Studio không có API: không kick", G._kicked == nil)
eq("Studio không có API: dữ liệu mặc định", svc.Data:Get(G).Money, 100)
local noSaveWarn = false
for _, w in warnings do if string.find(w, "KHÔNG LƯU", 1, true) then noSaveWarn = true end end
check("Studio không có API: có cảnh báo KHÔNG LƯU", noSaveWarn)
storeFail = false
svc.Data:_release(G)
check("Chế độ không lưu không ghi DataStore", storeData["u_7"] == nil)

storeFail, isStudio = true, false
local H = newPlayer(8, "Hank")
svc.Data:_load(H)
check("Server thật + tải lỗi: kick người chơi", H._kicked ~= nil)
eq("Thông báo kick tiếng Việt", H._kicked, Config.Text.DataLoadFailed)
check("Server thật + tải lỗi: không có dữ liệu để ghi đè", svc.Data:Get(H) == nil)
storeFail, isStudio = false, true

-- ═══════════════════════════ v0.2 ═══════════════════════════
local Calendar = fakeRequire(nodes["shared/Calendar"])
local Describe = fakeRequire(nodes["server/Util/Describe"])
local DAY = Config.Calendar.DayLengthSeconds
local function timeOn(weekday, week) return ((week or 0) * 7 + (weekday - 1)) * DAY + 1 end
local function fakeBasePart(position, size, attributes)
	return {
		_isInstance = true, Position = position, Size = size,
		IsA = function(_, c) return c == "BasePart" end,
		IsDescendantOf = function() return true end,
		GetAttribute = function(_, name) return attributes[name] end,
		GetFullName = function() return "fake" end,
	}
end

-- ═══════════════ 13. Lịch trong game ═══════════════
eq("Ngày game 0 là Thứ Hai", Calendar.GetWeekday(0), 1)
eq("Ngày game 6 là Chủ Nhật", Calendar.GetWeekday(6 * DAY), 7)
eq("Ngày game 7 quay về Thứ Hai", Calendar.GetWeekday(7 * DAY), 1)
eq("Cuối ngày game 2 vẫn là Thứ Tư", Calendar.GetWeekday(3 * DAY - 1), 3)
eq("Thứ Tư tuần thứ 5", Calendar.GetWeekday(timeOn(3, 5)), 3)
eq("Tên ngày 3", Calendar.DayName(3), "Thứ Tư")
eq("Gym mở Thứ Hai", Calendar.IsOpen(Config.Classes.gym.Days, timeOn(1)), true)
eq("Gym đóng Thứ Ba", Calendar.IsOpen(Config.Classes.gym.Days, timeOn(2)), false)
eq("FormatDays", Calendar.FormatDays({ 1, 3, 5 }), "T2, T4, T6")
for day = 1, 7 do
	local anyOpen = false
	for _, class in Config.Classes do
		if table.find(class.Days, day) then anyOpen = true end
	end
	check("Có ít nhất một lớp mở vào " .. Calendar.DayName(day), anyOpen)
end

-- ═══════════════ 14. Kỹ năng mới và nghề mở khóa theo level ═══════════════
local K = newPlayer(31, "Kim")
svc.Data:_load(K)
local dK = svc.Data:Get(K)
eq("Người mới có kỹ năng Trí tuệ", dK.Skills.Intelligence.Level, 0)
eq("Người mới có kỹ năng Khéo tay", dK.Skills.Dexterity.Level, 0)
eq("Người mới có cửa sổ trần quái", dK.Combat.Earned, 0)
eq("Tên nghề có điều kiện", Describe.JobTitle(Config.Jobs.technician), "Kỹ thuật viên (cần Khéo tay Lv.3)")
eq("Tên nghề không điều kiện", Describe.JobTitle(Config.Jobs.warehouse), "Bốc vác kho hàng")
eq("Điều kiện của Quản lý", Describe.Requirements(Config.Jobs.manager), "Trí tuệ Lv.5, Giao tiếp Lv.3")

local moneyK = dK.Money
svc.Jobs:_work(K, Config.Jobs.technician)
eq("Kỹ thuật viên bị khóa: không nhận tiền", dK.Money, moneyK)
eq("Thông báo khóa nghề", lastNotification(K).text, "Chưa mở khóa nghề này. Cần Khéo tay Lv.3 (bạn đang Lv.0).")
eq("Khóa nghề báo loại warning", lastNotification(K).kind, "warning")
near("Nghề bị khóa không trừ chỉ số", dK.Stats.Energy, 100)
dK.Skills.Dexterity.Level = 3
svc.Jobs:_work(K, Config.Jobs.technician)
eq("Kỹ thuật viên Lv3: lương = round(22 x 1.3) = 29", dK.Money - moneyK, 29)
eq("Kỹ thuật viên cộng XP Khéo tay", dK.Skills.Dexterity.XP, 10)
near("Kỹ thuật viên trừ Năng lượng 7", dK.Stats.Energy, 93)

dK.Skills.Intelligence.Level = 5
dK.Skills.Communication.Level = 2
moneyK = dK.Money
svc.Jobs:_work(K, Config.Jobs.manager)
eq("Quản lý khóa vì thiếu Giao tiếp", dK.Money, moneyK)
eq("Thông báo chỉ nêu kỹ năng còn thiếu", lastNotification(K).text, "Chưa mở khóa nghề này. Cần Giao tiếp Lv.3 (bạn đang Lv.2).")
dK.Skills.Communication.Level = 3
svc.Jobs:_work(K, Config.Jobs.manager)
eq("Quản lý mở khóa: lương = round(34 x 1.5) = 51", dK.Money - moneyK, 51)

-- ═══════════════ 15. Trường học ═══════════════
local L = newPlayer(32, "Lan")
svc.Data:_load(L)
local dL = svc.Data:Get(L)
serverTime = timeOn(1) -- Thứ Hai: gym mở, lớp kỹ năng mềm đóng
eq("Học phí Lv0 = $10", svc.School:GetTuition(L, "Strength"), 10)
svc.School:_attend(L, Config.Classes.gym)
eq("Học gym: trừ học phí $10", dL.Money, 90)
eq("Học gym: +30 XP", dL.Skills.Strength.XP, 30)
near("Học gym: Năng lượng -10", dL.Stats.Energy, 90)
near("Học gym: Độ no -5", dL.Stats.Hunger, 95)
near("Học gym: Sạch sẽ -6", dL.Stats.Hygiene, 94)
near("Học gym: Căng thẳng +2", dL.Stats.Stress, 12)
eq("Thông báo buổi học", lastNotification(L).text, "Buổi học Phòng gym: -$10 · +30 XP Sức mạnh")
svc.School:_attend(L, Config.Classes.gym)
eq("Buổi 2: lên Lv1", dL.Skills.Strength.Level, 1)
eq("Buổi 2: XP dư 10", dL.Skills.Strength.XP, 10)
eq("Buổi 2: học phí vẫn $10 (tính theo level lúc học)", dL.Money, 80)
eq("Học phí Lv1 = $20", svc.School:GetTuition(L, "Strength"), 20)
svc.School:_attend(L, Config.Classes.gym)
eq("Buổi 3: học phí $20", dL.Money, 60)

local moneyBeforeClosed = dL.Money
svc.School:_attend(L, Config.Classes.softskills)
eq("Lớp đóng cửa: không thu phí", dL.Money, moneyBeforeClosed)
eq("Thông báo lớp nghỉ", lastNotification(L).text, "Lớp kỹ năng mềm hôm nay nghỉ. Lớp mở vào: T3, T5, T7.")
serverTime = timeOn(2) -- Thứ Ba
svc.School:_attend(L, Config.Classes.softskills)
eq("Thứ Ba lớp kỹ năng mềm mở: trừ $10", dL.Money, moneyBeforeClosed - 10)
eq("Giao tiếp +30 XP", dL.Skills.Communication.XP, 30)

serverTime = timeOn(1)
dL.Money = 5
local xpBeforePoor = dL.Skills.Strength.XP
svc.School:_attend(L, Config.Classes.gym)
eq("Thiếu tiền: không bị trừ", dL.Money, 5)
eq("Thiếu tiền: không có XP", dL.Skills.Strength.XP, xpBeforePoor)
eq("Thông báo thiếu học phí", lastNotification(L).text, "Học phí buổi này là $20, bạn không đủ tiền.")
dL.Money, dL.Stats.Energy = 500, 14.9
svc.School:_attend(L, Config.Classes.gym)
eq("Quá mệt: không thu học phí", dL.Money, 500)
check("Quá mệt: có thông báo", string.find(lastNotification(L).text, "quá mệt", 1, true) ~= nil)
dL.Stats.Energy, dL.Skills.Strength.Level = 100, 20
svc.School:_attend(L, Config.Classes.gym)
eq("Kỹ năng tối đa: không thu phí", dL.Money, 500)
eq("Thông báo kỹ năng tối đa", lastNotification(L).text, "Bạn đã đạt cấp tối đa kỹ năng Sức mạnh, không cần học thêm.")

-- ═══════════════ 16. Đánh quái ═══════════════
eq("Sát thương Lv0", svc.Combat:GetDamage(0), 10)
eq("Sát thương Lv5", svc.Combat:GetDamage(5), 18)
eq("Sát thương Lv10", svc.Combat:GetDamage(10), 25)
eq("Sát thương Lv20", svc.Combat:GetDamage(20), 40)
near("Chu kỳ đánh khi Năng lượng 100", svc.Combat:GetAttackInterval(100), 1.0)
near("Chu kỳ đánh khi Năng lượng 50", svc.Combat:GetAttackInterval(50), 1.0)
near("Chu kỳ đánh khi Năng lượng 25", svc.Combat:GetAttackInterval(25), 1 / 0.75)
near("Chu kỳ đánh khi Năng lượng 0", svc.Combat:GetAttackInterval(0), 2.0)
near("Chia thưởng 1 người", svc.Combat:GetShare(1), 1.0)
near("Chia thưởng 2 người", svc.Combat:GetShare(2), 0.75)
near("Chia thưởng 3 người", svc.Combat:GetShare(3), 0.5)
near("Chia thưởng 4 người", svc.Combat:GetShare(4), 0.25)
near("Chia thưởng 6 người (sàn)", svc.Combat:GetShare(6), 0.25)

local slimePoint = fakeBasePart(Vector3.new(0, 0.5, 120), Vector3.new(5, 0.2, 5), { MonsterId = "slime" })
local bearPoint = fakeBasePart(Vector3.new(30, 0.5, 120), Vector3.new(5, 0.2, 5), { MonsterId = "bear" })
svc.Combat:_registerPoint(slimePoint)
svc.Combat:_registerPoint(bearPoint)
svc.Combat:_registerPoint(slimePoint)
eq("Dựng 2 quái (đăng ký trùng không dựng thêm)", #built, 2)
local slime = svc.Combat:GetMonster(built[1].Handle.Model)
local bear = svc.Combat:GetMonster(built[2].Handle.Model)
check("Slime đủ máu", slime ~= nil and slime.HP == 30)
check("Gấu đủ máu", bear ~= nil and bear.HP == 120)
check("Model không phải quái thì GetMonster là nil", svc.Combat:GetMonster({}) == nil)

local origInterval = Config.Combat.AttackInterval
local origSlimeRespawn = Config.Monsters.slime.RespawnSeconds
local M, rootM, humM = newPlayer(33, "Minh", Vector3.new(0, 3, 115))
svc.Data:_load(M)
local dM = svc.Data:Get(M)
svc.Combat:_attack(M, slime)
eq("Đòn đầu trừ 10 máu", slime.HP, 20)
check("Thanh máu được cập nhật", built[1].Handle.LastFraction ~= nil and math.abs(built[1].Handle.LastFraction - 20 / 30) < 1e-6)
svc.Combat:_attack(M, slime)
eq("Đánh quá nhanh bị chặn bởi chu kỳ", slime.HP, 20)

Config.Combat.AttackInterval = 0 -- bỏ chu kỳ để thử luồng hạ quái
Config.Monsters.slime.RespawnSeconds = 0
local moneyM = dM.Money
svc.Combat:_attack(M, slime)
svc.Combat:_attack(M, slime)
eq("Slime bị hạ", slime.HP, 0)
check("Model slime bị gỡ", built[1].Handle.Model.Destroyed)
check("Quái đã hạ không còn tra được", svc.Combat:GetMonster(built[1].Handle.Model) == nil)
eq("Thưởng tiền Slime +$12", dM.Money - moneyM, 12)
eq("Thưởng XP Slime +12", dM.Skills.Strength.XP, 12)
near("Chi phí hạ Slime: Năng lượng -6", dM.Stats.Energy, 94)
near("Chi phí hạ Slime: Độ no -4", dM.Stats.Hunger, 96)
near("Chi phí hạ Slime: Căng thẳng +5", dM.Stats.Stress, 15)
eq("Thông báo hạ quái", lastNotification(M).text, "Hạ Slime Kẹo: +$12 · +12 XP Sức mạnh")
svc.Combat:_attack(M, slime)
eq("Đánh quái đã chết không nhận thêm", dM.Money - moneyM, 12)
svc.Combat:_tickMonsters()
eq("Slime hồi sinh sau tick", #built, 3)
local slime2 = svc.Combat:GetMonster(built[3].Handle.Model)
check("Slime mới đủ máu", slime2 ~= nil and slime2.HP == 30)

-- Quái đánh người chơi
local t0 = os.clock()
humM.Health = 100
svc.Combat:_monsterAct(slime2, t0 + 100)
eq("Quái đánh người trong tầm: -5 máu", humM.Health, 95)
svc.Combat:_monsterAct(slime2, t0 + 100)
eq("Chưa hết chu kỳ: quái không đánh", humM.Health, 95)
svc.Combat:_monsterAct(slime2, t0 + 103)
eq("Hết chu kỳ 2 giây: quái đánh tiếp", humM.Health, 90)
rootM.Position = Vector3.new(0, 3, 150)
svc.Combat:_monsterAct(slime2, t0 + 110)
eq("Người ngoài tầm không bị đánh", humM.Health, 90)
rootM.Position = Vector3.new(0, 3, 115)
humM.Health = 0
svc.Combat:_monsterAct(slime2, t0 + 120)
eq("Người đã chết không bị đánh tiếp", humM.Health, 0)

-- Thua trận: phí + hồi sinh ở Bệnh xá
taggedInstances[Config.Tags.Infirmary] = { fakeBasePart(Vector3.new(-75, 3, 120), Vector3.new(14, 6, 14), {}) }
local moneyBeforeDefeat = dM.Money
svc.Combat:_onDeath(M)
eq("Thua trận: phí $10", moneyBeforeDefeat - dM.Money, 10)
eq("Thông báo thua trận", lastNotification(M).text, "Bạn bị Slime Kẹo đánh bại! Phí Bệnh xá $10, bạn sẽ hồi sinh tại Bệnh xá.")
svc.Combat:_onDeath(M)
eq("Chỉ thu phí một lần cho một lần thua", moneyBeforeDefeat - dM.Money, 10)
local charM = M.Character
svc.Combat:_onCharacterAdded(M, charM)
eq("Hồi sinh ở Bệnh xá: có đúng một lần PivotTo", #charM._pivots, 1)
local landing = charM._pivots[1].Position
check("Vị trí Bệnh xá (trước cửa, cách đất 4)", landing.X == -75 and landing.Y == 4 and landing.Z == 109, `{landing.X},{landing.Y},{landing.Z}`)
svc.Combat:_onCharacterAdded(M, charM)
eq("Lần hồi sinh sau không bị đưa tới Bệnh xá", #charM._pivots, 1)
check("Kiệt sức/chết thường không tính là thua trận", select(1, pcall(svc.Combat._onDeath, svc.Combat, E)) == true)

-- Phí không bao giờ làm âm tiền
humM.Health = 100
rootM.Position = Vector3.new(0, 3, 115)
svc.Combat:_monsterAct(slime2, t0 + 200)
dM.Money = 4
svc.Combat:_onDeath(M)
eq("Phí thua trận tối đa bằng số tiền đang có", dM.Money, 0)

-- Chết quá DefeatWindowSeconds sau đòn cuối: không phải thua trận
rootM.Position = Vector3.new(30, 3, 115)
humM.Health = 100
svc.Combat:_monsterAct(bear, os.clock() - 100)
dM.Money = 50
svc.Combat:_onDeath(M)
eq("Đòn đã cũ: không tính là thua trận", dM.Money, 50)

-- Chia thưởng nhiều người cùng hạ một quái
local P1 = newPlayer(41, "P1", Vector3.new(30, 3, 115))
local P2 = newPlayer(42, "P2", Vector3.new(30, 3, 115))
local P3 = newPlayer(43, "P3", Vector3.new(30, 3, 115))
for _, p in { P1, P2, P3 } do svc.Data:_load(p) end
local dP1, dP2, dP3 = svc.Data:Get(P1), svc.Data:Get(P2), svc.Data:Get(P3)
for _ = 1, 1 do svc.Combat:_attack(P3, bear) end
for _ = 1, 6 do svc.Combat:_attack(P1, bear) end
for _ = 1, 5 do svc.Combat:_attack(P2, bear) end
eq("Gấu bị hạ", bear.HP, 0)
eq("Người tham gia 1 nhận 75% = $38", dP1.Money - 100, 38)
eq("Người tham gia 2 nhận 75% = $38", dP2.Money - 100, 38)
eq("Người tham gia 1 nhận 30 XP", dP1.Skills.Strength.XP, 30)
eq("Người chỉ đánh 1 đòn (dưới 10%) không nhận tiền", dP3.Money, 100)
eq("Người chỉ đánh 1 đòn không nhận XP", dP3.Skills.Strength.XP, 0)
near("Chi phí hạ Gấu: Năng lượng -20", dP1.Stats.Energy, 80)
near("Chi phí hạ Gấu: Căng thẳng +14", dP1.Stats.Stress, 24)
eq("Thông báo hạ Gấu", lastNotification(P1).text, "Hạ Gấu Bông: +$38 · +30 XP Sức mạnh")

-- Trần tiền kiếm từ quái
local Q = newPlayer(44, "Q", Vector3.new(0, 3, 115))
svc.Data:_load(Q)
local dQ = svc.Data:Get(Q)
dQ.Combat = { WindowStart = os.time(), Earned = Config.Combat.HourlyMoneyCap - 10 }
for _ = 1, 3 do svc.Combat:_attack(Q, slime2) end
eq("Gần chạm trần: chỉ nhận phần còn lại $10", dQ.Money - 100, 10)
eq("Cửa sổ trần đã đầy", dQ.Combat.Earned, Config.Combat.HourlyMoneyCap)
eq("Thông báo nhận phần còn lại", lastNotification(Q).text, "Hạ Slime Kẹo: +$10 · +12 XP Sức mạnh")
svc.Combat:_tickMonsters()
local slime3 = svc.Combat:GetMonster(built[#built].Handle.Model)
for _ = 1, 3 do svc.Combat:_attack(Q, slime3) end
eq("Chạm trần: không nhận thêm tiền", dQ.Money - 100, 10)
eq("Chạm trần: vẫn nhận XP", dQ.Skills.Strength.XP, 24)
eq("Thông báo chạm trần", lastNotification(Q).text, "Hạ Slime Kẹo: +12 XP Sức mạnh (đã chạm trần tiền từ quái trong giờ này)")
eq("Thông báo chạm trần loại warning", lastNotification(Q).kind, "warning")
dQ.Combat.WindowStart = os.time() - Config.Combat.CapWindowSeconds - 1
svc.Combat:_tickMonsters()
local slime4 = svc.Combat:GetMonster(built[#built].Handle.Model)
for _ = 1, 3 do svc.Combat:_attack(Q, slime4) end
eq("Hết cửa sổ: trần được làm mới, nhận đủ $12", dQ.Money - 100, 22)
eq("Cửa sổ mới bắt đầu từ lần kiếm này", dQ.Combat.Earned, 12)
check("WindowStart được đặt lại gần hiện tại", math.abs(dQ.Combat.WindowStart - os.time()) <= 2)

-- Gỡ điểm xuất hiện thì gỡ luôn quái đang sống
svc.Combat:_tickMonsters()
local liveSlime = svc.Combat:GetMonster(built[#built].Handle.Model)
check("Có quái sống trước khi gỡ điểm", liveSlime ~= nil)
svc.Combat:_unregisterPoint(slimePoint)
check("Gỡ điểm xuất hiện: quái bị gỡ", built[#built].Handle.Model.Destroyed)
Config.Combat.AttackInterval = origInterval
Config.Monsters.slime.RespawnSeconds = origSlimeRespawn

-- ═══════════════ 17. Dữ liệu cũ thiếu trường v0.2 ═══════════════
storeData["u_60"] = { SchemaVersion = 1, Money = 500, Stats = deepCopy(Config.Stats.Start), Skills = { Strength = { Level = 2, XP = 5 } }, Owned = {} }
local R = newPlayer(60, "Rin")
svc.Data:_load(R)
local dR = svc.Data:Get(R)
eq("Dữ liệu cũ được bổ sung Combat", dR.Combat.Earned, 0)
eq("Dữ liệu cũ được bổ sung Trí tuệ", dR.Skills.Intelligence.Level, 0)
eq("Dữ liệu cũ được bổ sung Khéo tay", dR.Skills.Dexterity.Level, 0)
eq("Dữ liệu cũ giữ nguyên Sức mạnh", dR.Skills.Strength.Level, 2)
storeData["u_61"] = { Money = 100, Combat = { WindowStart = "x", Earned = -5 } }
local S = newPlayer(61, "Sam")
svc.Data:_load(S)
eq("Combat sai kiểu về mặc định", svc.Data:Get(S).Combat.Earned, 0)
storeData["u_62"] = { Money = 100, Combat = { WindowStart = 10, Earned = -5 } }
local T = newPlayer(62, "Tuan")
svc.Data:_load(T)
eq("Combat.Earned âm bị chặn về 0", svc.Data:Get(T).Combat.Earned, 0)
eq("Combat.WindowStart hợp lệ được giữ", svc.Data:Get(T).Combat.WindowStart, 10)

-- ═══════════════ 18. Bảng xếp hạng (chế độ cục bộ: DataStore xếp hạng không khả dụng) ═══════════════
local boardPart = fakeBasePart(Vector3.new(0, 8, 45), Vector3.new(28, 16, 1), {})
taggedInstances[Config.Tags.Leaderboard] = { boardPart }
local worthB = dB.Money + 800
eq("Tài sản ròng = tiền + giá đồ vĩnh viễn", svc.Leaderboard:GetNetWorth(B), worthB)
eq("Tài sản ròng người chưa có đồ = tiền", svc.Leaderboard:GetNetWorth(Q), dQ.Money)
svc.Leaderboard:_refresh()
eq("Bob đứng hạng 1", svc.Leaderboard:GetRank(B), 1)
eq("Alice đứng hạng 2 (777 + kính râm 200)", svc.Leaderboard:GetRank(A2), 2)
check("Người chưa có dữ liệu không có hạng", svc.Leaderboard:GetRank(E) == nil)
local view = svc.Leaderboard:GetView(B)
eq("Chế độ cục bộ báo IsLocal", view.IsLocal, true)
eq("Hạng của Bob trong view", view.SelfRank, 1)
eq("Tài sản ròng của Bob trong view", view.SelfNetWorth, worthB)
eq("Dòng đầu là Bob", view.Entries[1].Name, "Bob")
local sorted = true
for i = 2, #view.Entries do
	if view.Entries[i - 1].NetWorth < view.Entries[i].NetWorth then sorted = false end
	if view.Entries[i].Rank ~= i then sorted = false end
end
check("Bảng sắp giảm dần và hạng liên tục", sorted)
check("Không vượt quá TopCount", #view.Entries <= Config.Leaderboard.TopCount)
local boardText = boardWrites[boardPart]
check("Bảng 3D có tiêu đề", boardText ~= nil and string.find(boardText, "BẢNG XẾP HẠNG TÀI SẢN", 1, true) ~= nil)
check("Bảng 3D có hàng đầu", boardText ~= nil and string.find(boardText, "1. Bob · $1.000", 1, true) ~= nil, boardText)
check("Bảng 3D ghi chú chế độ cục bộ", boardText ~= nil and string.find(boardText, "(chỉ gồm người chơi trong máy chủ này)", 1, true) ~= nil)
local snapB = svc.Replication:BuildSnapshot(B)
eq("Snapshot có tài sản ròng", snapB.NetWorth, worthB)
eq("Snapshot có hạng", snapB.Rank, 1)
check("Người chưa có hạng: snapshot Rank = nil", svc.Replication:BuildSnapshot(Q).Rank == nil or svc.Leaderboard:GetRank(Q) ~= nil)

-- ═══════════════ 19. Bảng xếp hạng (chế độ OrderedDataStore) ═══════════════
orderedUnavailable = false
orderedData["u_500"] = 5000
orderedData["u_501"] = 50
nameLookup[500] = "Remote500" -- 501 cố ý không có: thử tên dự phòng
local lb = loadFresh("server/Services/LeaderboardService")
lb:Init(svc)
lb:_publish(2, 1000)
eq("Ghi lên OrderedDataStore", orderedData["u_2"], 1000)
lb:_publish(3, 123.7)
eq("Số lẻ được làm tròn xuống", orderedData["u_3"], 123)
local warnsBefore = #warnings
lb:_publish(2, 1000 + Config.Leaderboard.SuspiciousJump + 1)
local flagged = false
for i = warnsBefore + 1, #warnings do
	if string.find(warnings[i], "Nghi vấn", 1, true) then flagged = true end
end
check("Tăng đột biến bị ghi cảnh báo nghi vấn", flagged)
eq("Vẫn ghi giá trị (chỉ cảnh báo, không chặn)", orderedData["u_2"], 1000 + Config.Leaderboard.SuspiciousJump + 1)
lb:_refresh()
local view2 = lb:GetView(B)
eq("Chế độ DataStore: không phải bảng cục bộ", view2.IsLocal, false)
eq("Hạng 1 là người ngoài server (5000)", view2.Entries[1].UserId, 500)
eq("Tên lấy từ GetNameFromUserIdAsync", view2.Entries[1].Name, "Remote500")
eq("Bob dùng giá trị MỚI trong server (không dùng giá trị ghi cũ)", lb:GetRank(B), 2)
eq("Giá trị của Bob trong bảng là tài sản hiện tại", view2.Entries[2].NetWorth, worthB)
local fallbackName
for _, entry in view2.Entries do
	if entry.UserId == 501 then fallbackName = entry.Name end
end
eq("Không tra được tên thì dùng tên dự phòng", fallbackName, "Người chơi 501")
orderedFail = true
lb:_refresh()
eq("DataStore lỗi: quay về bảng cục bộ", lb:GetView(B).IsLocal, true)
local okPublish = pcall(function() lb:_publish(2, 5) end)
check("Ghi thất bại không ném lỗi", okPublish)
orderedFail = false
orderedUnavailable = true

-- ═══════════════════════════ v0.3: AURA ═══════════════════════════
local function lastNotif(player) local n = lastNotification(player) return n and n.text or "" end
local function loadNew(id, name, pos, money)
	local p, root = newPlayer(id, name, pos)
	svc.Data:_load(p)
	local d = svc.Data:Get(p)
	if money then d.Money = money end
	return p, d, root
end

-- ═══════════════ 20. Công thức thuế ═══════════════
eq("Hệ số chính sách ban đầu = 1", svc.Aura:GetPolicyMultiplier(), 1)
eq("Thuế $3.000 = 0", svc.Aura:ComputeTax(3000), 0)
eq("Thuế $5.000 = 0", svc.Aura:ComputeTax(5000), 0)
eq("Thuế $10.000 = 50", svc.Aura:ComputeTax(10000), 50)
eq("Thuế $20.000 = 150", svc.Aura:ComputeTax(20000), 150)
eq("Thuế $50.000 = 1.050", svc.Aura:ComputeTax(50000), 1050)
eq("Thuế $100.000 = 2.550", svc.Aura:ComputeTax(100000), 2550)
eq("Thuế $200.000 = 8.550", svc.Aura:ComputeTax(200000), 8550)

-- ═══════════════ 21. Sự kiện ═══════════════
serverTime = 0
check("Bắt đầu Khủng hoảng lương thực", svc.Aura:StartEvent("food_crisis", 0))
check("Không chồng hai sự kiện", not svc.Aura:StartEvent("food_sale", 0))
near("Giá đồ ăn x1,5", svc.Aura:GetPriceMultiplier("food"), 1.5)
near("Giá thời trang không đổi", svc.Aura:GetPriceMultiplier("fashion"), 1)
eq("Trạng thái AURA có sự kiện", svc.Aura:GetState().Event.Id, "food_crisis")
near("Trạng thái có hệ số giá đồ ăn", svc.Aura:GetState().PriceMultipliers.food, 1.5)
rootB.Position = Vector3.new(0, 0, 0)
local moneyBeforeCrisis = dB.Money
local okCrisis, msgCrisis = svc.Shop:_buy(B, "restaurant", "banh_mi")
check("Mua bánh mì trong khủng hoảng", okCrisis, msgCrisis)
eq("Khủng hoảng: bánh mì $15", moneyBeforeCrisis - dB.Money, 15)
eq("Thông báo dùng giá thực tế", msgCrisis, "Đã mua Bánh mì (-$15).")
svc.Aura:_tick(600) -- hết 10 phút: sự kiện kết thúc (đồng thời chạy chu kỳ 1)
check("Sự kiện hết hạn", svc.Aura:GetState().Event == nil)
near("Giá đồ ăn về x1", svc.Aura:GetPriceMultiplier("food"), 1)

-- Thiếu lao động: nghề ít người làm nhất (trong số nghề có người làm được) được +25% lương
svc.Aura:NoteWork(A2, "warehouse")
svc.Aura:NoteWork(B, "barista")
svc.Aura:NoteWork(C, "technician")
eq("Đếm người đang làm kho hàng", svc.Aura:CountActiveWorkers().warehouse, 1)
check("Bắt đầu Thiếu lao động", svc.Aura:StartEvent("labor_shortage", 2410))
near("Quản lý (0 người làm) được x1,25", svc.Aura:GetPayMultiplier("manager"), 1.25)
near("Kho hàng không được thưởng", svc.Aura:GetPayMultiplier("warehouse"), 1)
check("Thông báo nêu tên nghề", string.find(lastNotif(K), "Quản lý", 1, true) ~= nil, lastNotif(K))
local moneyKim = dK.Money
dK.Stats.Energy = 100
svc.Jobs:_work(K, Config.Jobs.manager, "manager")
eq("Quản lý Lv5 + thưởng: round(34 x 1,5 x 1,25) = 64", dK.Money - moneyKim, 64)
svc.Aura:_tick(3010)
check("Thiếu lao động hết hạn", svc.Aura:GetState().Event == nil)

-- ═══════════════ 22. Thuê, trả lại, phí duy trì, thu hồi ═══════════════
local U, dU = loadNew(71, "Uyen", Vector3.new(0, 0, 0), 5000)
local ok, msg = svc.Assets:Lease(U, "boarding")
check("Thuê Phòng trọ", ok, msg)
eq("Thuê: trừ giá $1.000", dU.Money, 4000)
eq("Thông báo thuê", msg, "Đã thuê Phòng trọ (-$1.000). Nổi tiếng +20, phí duy trì $10 mỗi chu kỳ.")
check("Dữ liệu có tài sản", dU.Assets.boarding ~= nil and dU.Assets.boarding.Missed == 0)
eq("Thuê trùng bị từ chối", select(2, svc.Assets:Lease(U, "boarding")), "Bạn đang thuê tài sản này rồi.")
eq("Tài sản hiếm không thuê trực tiếp", select(2, svc.Assets:Lease(U, "villa")), "Tài sản hiếm chỉ có thể có được qua đấu giá.")
eq("Tài sản không tồn tại", select(2, svc.Assets:Lease(U, "castle")), "Yêu cầu không hợp lệ.")
eq("Không đủ tiền thuê", select(2, svc.Assets:Lease(U, "car")), "Bạn không đủ tiền.")
eq("Nổi tiếng từ tài sản", svc.Assets:GetFame(U), 20)
eq("Tài sản ròng tính giá thuê", svc.Leaderboard:GetNetWorth(U), 5000)
local snapU = svc.Replication:BuildSnapshot(U)
eq("Snapshot: Nổi tiếng gồm tài sản", snapU.Fame, 20)
eq("Snapshot: tài sản đang thuê", snapU.Assets.boarding, 0)
eq("Phí duy trì mỗi chu kỳ", svc.Assets:GetUpkeep(U), 10)

svc.Assets:ProcessCycle(U, dU)
eq("Chu kỳ: trừ phí $10", dU.Money, 3990)
eq("Thông báo thu phí", lastNotif(U), "AURA thu phí duy trì: -$10.")
dU.Money = 0
svc.Assets:ProcessCycle(U, dU)
eq("Thiếu tiền: ghi nợ 1 chu kỳ", dU.Assets.boarding.Missed, 1)
eq("Cảnh báo nợ", lastNotif(U), "Thiếu phí duy trì $20 cho Phòng trọ. Còn 3 chu kỳ ân hạn trước khi bị thu hồi.")
svc.Assets:ProcessCycle(U, dU)
svc.Assets:ProcessCycle(U, dU)
eq("Nợ 3 chu kỳ vẫn còn tài sản", dU.Assets.boarding.Missed, 3)
dU.Money = 35
svc.Assets:ProcessCycle(U, dU)
eq("Trả bù 4 chu kỳ ($40) khi chỉ có $35: chưa đủ -> thu hồi", dU.Assets.boarding, nil)
eq("Thông báo thu hồi", lastNotif(U), "AURA đã thu hồi Phòng trọ vì nợ phí duy trì quá 3 chu kỳ.")
eq("Thu hồi không phạt thêm tiền", dU.Money, 35)
dU.Money = 10000
svc.Assets:Lease(U, "car")
dU.Assets.car.Missed = 2
svc.Assets:ProcessCycle(U, dU)
eq("Trả bù: 3 x $60 = $180", dU.Money, 10000 - 5000 - 180)
eq("Trả bù xong thì hết nợ", dU.Assets.car.Missed, 0)
local okRet, msgRet = svc.Assets:Return(U, "car")
check("Trả lại tài sản", okRet)
eq("Thông báo trả lại", msgRet, "Đã trả lại Ô tô cho AURA.")
eq("Trả lại không hoàn tiền", dU.Money, 4820)
eq("Trả cái không thuê", select(2, svc.Assets:Return(U, "car")), "Bạn không thuê tài sản này.")

-- ═══════════════ 23. Thu thuế ═══════════════
local V, dV = loadNew(72, "Vy", Vector3.new(0, 0, 0), 20000)
svc.Aura:_collectTax(V, false)
eq("Thuế tài sản ròng $20.000 = $150", dV.Money, 19850)
eq("Thông báo thuế", lastNotif(V), "AURA thu thuế: -$150 (tài sản ròng $20.000).")
dV.Money = 9500
svc.Assets:Lease(V, "apartment") -- 5.500 tiền + 4.000 giá thuê = 9.500 tài sản ròng
svc.Aura:_collectTax(V, true)
eq("Ngày không thuế: không thu", dV.Money, 5500)
eq("Thông báo miễn thuế", lastNotif(V), "Ngày không thuế: AURA miễn thuế kỳ này.")
dV.Money = 10
svc.Aura:_collectTax(V, false) -- tài sản ròng 4.010: dưới ngưỡng
eq("Dưới $5.000 không thu thuế", dV.Money, 10)
svc.Assets:ProcessCycle(V, dV) -- không đủ phí: nợ
dV.Money = 20
dV.Assets.apartment.Missed = 0
local Vx, dVx = loadNew(73, "Vx", Vector3.new(0, 0, 0), 30)
dVx.Owned.gold_watch = true
dVx.Owned.sunglasses = true
svc.Assets:Lease(Vx, "boarding") -- không đủ tiền: không thuê được
dVx.Assets.apartment = { LeasedAt = os.time(), Missed = 0 }
dVx.Assets.car = { LeasedAt = os.time(), Missed = 0 }
-- tài sản ròng = 30 + 800 + 9.000 = 9.830 -> thuế 48, chỉ có $30
svc.Aura:_collectTax(Vx, false)
eq("Thuế chỉ thu tối đa số tiền đang có", dVx.Money, 0)

-- ═══════════════ 24. Mỗi chu kỳ chỉ xử lý một lần cho mỗi người ═══════════════
local Wp, dW = loadNew(74, "Wen", Vector3.new(0, 0, 0), 10000)
svc.Assets:Lease(Wp, "motorbike") -- 9.200
svc.Aura:_onCycle(13, 13 * 600)
eq("Chu kỳ 13: trừ phí xe máy $8", dW.Money, 9192)
eq("Ghi lại chu kỳ đã xử lý", dW.Aura.LastCycle, 13)
svc.Aura:_onCycle(13, 13 * 600)
eq("Chạy lại cùng chu kỳ không trừ lần nữa", dW.Money, 9192)

-- Ngày không thuế áp cho kỳ thuế kế tiếp rồi tự hết
check("Bắt đầu Ngày không thuế", svc.Aura:StartEvent("tax_holiday", 13 * 600))
eq("Trạng thái báo miễn thuế", svc.Aura:GetState().TaxExempt, true)
eq("Thuế dự kiến khi được miễn = 0", svc.Aura:GetView(Wp).ExpectedTax, 0)
local moneyW = dW.Money
local feeW = svc.Assets:GetFee("motorbike") -- tính trước: chu kỳ 15 cũng là kỳ kiểm tra lạm phát
svc.Aura:_onCycle(15, 15 * 600) -- kỳ thuế (15 chia hết cho 3)
eq("Kỳ thuế được miễn: chỉ trừ phí duy trì", moneyW - dW.Money, feeW)
eq("Miễn thuế chỉ áp một kỳ", svc.Aura:GetState().TaxExempt, false)

-- ═══════════════ 25. Đấu giá tài sản hiếm ═══════════════
serverTime = 100000
check("Mở phiên đấu giá", svc.Auction:Open())
check("Không mở phiên thứ hai cùng lúc", not svc.Auction:Open())
local auction = svc.Auction:GetState()
local rareId = auction.AssetId
local rareDef = Config.Assets[rareId]
check("Phiên dành cho tài sản hiếm", rareDef.Stock ~= nil, rareId)
eq("Giá khởi điểm = 60%", auction.StartPrice, math.floor(rareDef.Price * 0.6 + 0.5))
eq("Giá tối thiểu đầu tiên = khởi điểm", auction.MinNextBid, auction.StartPrice)

local X1, dX1 = loadNew(81, "X1", Vector3.new(0, 0, 0), 100000)
local X2, dX2 = loadNew(82, "X2", Vector3.new(0, 0, 0), 100000)
local start = auction.StartPrice
eq("Đặt giá thấp hơn khởi điểm", select(2, svc.Auction:Bid(X1, start - 1)), "Giá tối thiểu hiện tại là " .. Format.money(start) .. ".")
check("X1 đặt giá khởi điểm", svc.Auction:Bid(X1, start))
local fee1 = math.floor(start * 0.02 + 0.5)
eq("Khóa tiền + phí đặt giá", dX1.Money, 100000 - start - fee1)
check("Tiền khóa được ghi vào dữ liệu", dX1.Aura.Escrow ~= nil and dX1.Aura.Escrow.Amount == start)
eq("Đang dẫn đầu không đặt chồng", select(2, svc.Auction:Bid(X1, start * 2)), "Bạn đang dẫn đầu phiên đấu giá này.")
local minNext = svc.Auction:GetState().MinNextBid
eq("Bước tăng tối thiểu 10%", minNext, math.ceil(start * 1.1))
check("X2 vượt giá", svc.Auction:Bid(X2, minNext))
eq("X1 được hoàn tiền (phí không hoàn)", dX1.Money, 100000 - fee1)
check("Tiền khóa của X1 được xoá", dX1.Aura.Escrow == nil)
check("X1 được báo bị vượt giá", string.find(lastNotif(X1), "vượt giá", 1, true) ~= nil)
eq("Giá cao nhất là của X2", svc.Auction:GetState().HighestBidderName, "X2")

-- Chống chốt phút chót
serverTime = svc.Auction:GetState().EndsAt - 5
local endsBefore = svc.Auction:GetState().EndsAt
check("X1 đặt giá ở 5 giây cuối", svc.Auction:Bid(X1, svc.Auction:GetState().MinNextBid))
eq("Phiên được cộng thêm 10 giây", svc.Auction:GetState().EndsAt, endsBefore + 10)
local winningBid = svc.Auction:GetState().HighestBid
local x1Before = dX1.Money

-- Chốt phiên: người thắng nhận tài sản, tiền thắng bị hủy
serverTime = svc.Auction:GetState().EndsAt + 1
svc.Auction:_settle()
check("Không còn phiên", svc.Auction:GetState() == nil)
check("Người thắng nhận tài sản hiếm", dX1.Assets[rareId] ~= nil)
check("Tiền khóa đã dùng (xoá)", dX1.Aura.Escrow == nil)
eq("Tiền thắng không được hoàn", dX1.Money, x1Before)
eq("X2 đã được hoàn khi bị vượt", dX2.Money, 100000 - math.floor(minNext * 0.02 + 0.5))
eq("Kho còn lại giảm 1", svc.Assets:GetRemaining(rareId), rareDef.Stock - 1)
check("Thông báo thắng", string.find(lastNotif(X1), "thắng đấu giá", 1, true) ~= nil, lastNotif(X1))
eq("Nổi tiếng từ tài sản hiếm", svc.Assets:GetFame(X1), rareDef.Fame)

-- Phiên không ai đặt giá
check("Mở phiên mới", svc.Auction:Open())
serverTime = svc.Auction:GetState().EndsAt + 1
svc.Auction:_settle()
check("Phiên không người đặt thì kết thúc", svc.Auction:GetState() == nil)

-- Hết kho trong lúc đấu giá (server khác đã nhận hết): hoàn tiền, phí không hoàn
check("Mở phiên để thử hết kho", svc.Auction:Open())
local soldId = svc.Auction:GetState().AssetId
local Y, dY = loadNew(83, "Yen", Vector3.new(0, 0, 0), 100000)
local bidY = svc.Auction:GetState().MinNextBid
svc.Auction:Bid(Y, bidY)
local reg = storeData["registry"] or {}
for assetId, def in Config.Assets do -- server khác đã nhận hết mọi tài sản hiếm
	if def.Stock then
		local holders = reg[assetId] or {}
		for i = 1, def.Stock do holders["9000" .. i] = true end
		reg[assetId] = holders
	end
end
storeData["registry"] = reg
serverTime = svc.Auction:GetState().EndsAt + 1
svc.Auction:_settle()
check("Hết kho: không cấp tài sản", dY.Assets[soldId] == nil)
eq("Hết kho: hoàn giá, giữ phí", dY.Money, 100000 - math.floor(bidY * 0.02 + 0.5))
check("Hết kho: tiền khóa được xoá", dY.Aura.Escrow == nil)
eq("Mở phiên khi hết sạch kho thì từ chối", svc.Auction:Open(), false)
eq("Thông báo hết kho", lastNotif(Y), "AURA: không còn tài sản hiếm nào để đấu giá.")

-- Registry: nhận trùng không tăng số lượng
storeData["registry"] = nil
local Reg = fakeRequire(nodes["server/Util/AssetRegistry"])
local reg2 = Reg.new()
reg2:Init()
check("Nhận lần đầu", (reg2:TryClaim("villa", 5)))
check("Nhận lại cùng người: vẫn thành công", (reg2:TryClaim("villa", 5)))
eq("Nhận trùng không tăng số", reg2:Count("villa"), 1)
reg2:TryClaim("villa", 6)
reg2:TryClaim("villa", 7)
local okFull, whyFull = reg2:TryClaim("villa", 8)
check("Vượt kho bị từ chối", not okFull and whyFull == "sold_out", tostring(whyFull))
check("Trả về kho", reg2:Release("villa", 5))
eq("Còn lại sau khi trả", reg2:Remaining("villa"), 1)

-- Hoàn tiền khóa còn sót khi vào lại game
storeData["u_90"] = { Money = 100, Aura = { LastCycle = 0, Escrow = { AuctionId = "old-1", AssetId = "villa", Amount = 1234 } } }
local E2 = newPlayer(90, "Esc")
svc.Data:_load(E2)
-- Chỉ để đăng ký OnLoaded (người chơi đã tải xong nên được gọi ngay). Vòng lặp nền của Start không có
-- tham số nên bị bỏ qua, tránh chạy vô hạn với task.spawn đồng bộ của harness.
local realSpawn = task.spawn
task.spawn = function(f, ...) if select("#", ...) > 0 then realSpawn(f, ...) end end
svc.Auction:Start()
task.spawn = realSpawn
local dE2 = svc.Data:Get(E2)
eq("Vào lại: hoàn tiền khóa", dE2.Money, 1334)
check("Vào lại: xoá tiền khóa", dE2.Aura.Escrow == nil)

-- ═══════════════ 26. Dữ liệu v0.3 ═══════════════
storeData["u_91"] = { Money = 100, Assets = { castle = { LeasedAt = 1, Missed = 0 }, car = { LeasedAt = "x", Missed = 2 } }, Aura = { LastCycle = "x", Escrow = { AuctionId = 5 } } }
local G2 = newPlayer(91, "Gia")
svc.Data:_load(G2)
local dG2 = svc.Data:Get(G2)
check("Tài sản không còn trong Config bị bỏ", dG2.Assets.castle == nil)
eq("Tài sản hỏng được đặt lại", dG2.Assets.car.Missed, 0)
eq("LastCycle hỏng về 0", dG2.Aura.LastCycle, 0)
check("Escrow hỏng bị bỏ", dG2.Aura.Escrow == nil)
local H2 = newPlayer(92, "Hai")
svc.Data:_load(H2)
check("Người mới có Assets rỗng và Aura", next(svc.Data:Get(H2).Assets) == nil and svc.Data:Get(H2).Aura.LastCycle == 0)

-- ═══════════════ 27. Bộ điều chỉnh lạm phát ═══════════════
local saved = {}
local function setAllMoney(value)
	for _, p in PlayersService._list do
		local d = svc.Data:Get(p)
		if d then
			if saved[p] == nil then saved[p] = d.Money end
			d.Money = value
		end
	end
end
local p0 = svc.Aura:GetPolicyMultiplier() -- có thể đã đổi ở chu kỳ 15
setAllMoney(10000) -- gấp đôi mục tiêu: tăng tối đa 10%
svc.Aura:_adjustInflation(0)
near("Lạm phát: hệ số tăng 10%", svc.Aura:GetPolicyMultiplier(), p0 * 1.1)
local logNow = svc.Aura:GetState().Log
check("Ghi nhật ký điều chỉnh", string.find(logNow[#logNow].Text, "tăng", 1, true) ~= nil, logNow[#logNow].Text)
setAllMoney(5200) -- lệch 4%: trong vùng chết
svc.Aura:_adjustInflation(0)
near("Trong vùng chết: giữ nguyên", svc.Aura:GetPolicyMultiplier(), p0 * 1.1)
setAllMoney(4000) -- 0,8 lần mục tiêu: giảm 5%
svc.Aura:_adjustInflation(0)
local p1 = p0 * 1.1 * 0.95
near("Giảm phát: hệ số giảm 5%", svc.Aura:GetPolicyMultiplier(), p1)
eq("Phí nhân hệ số chính sách", svc.Assets:GetFee("car"), math.floor(60 * p1 + 0.5))
eq("Thuế nhân hệ số chính sách", svc.Aura:ComputeTax(20000), math.floor(150 * p1 + 0.5))
for _ = 1, 40 do setAllMoney(100) svc.Aura:_adjustInflation(0) end
near("Hệ số không thấp hơn sàn 0,5", svc.Aura:GetPolicyMultiplier(), 0.5)
for _ = 1, 30 do setAllMoney(100000) svc.Aura:_adjustInflation(0) end
near("Hệ số không vượt trần 2,0", svc.Aura:GetPolicyMultiplier(), 2.0)
for p, m in saved do svc.Data:Get(p).Money = m end

-- Báo cáo tiền vào/ra
local flowState = svc.Aura:GetState()
check("Trạng thái có số liệu báo cáo", type(flowState.Inflow) == "number" and type(flowState.Outflow) == "number")

-- ═══════════════ 25. Remote AURA: kiểm tra khoảng cách phía server ═══════════════
do
	taggedInstances[Config.Tags.Aura] = { fakeBasePart(Vector3.new(65, 3, 55), Vector3.new(18, 12, 14), {}) }
	if not remoteFunctions.AssetLease.OnServerInvoke then svc.Assets:Start() end
	local Far, dFar = loadNew(950, "Far", Vector3.new(0, 0, 0), 5000)
	local lease = remoteFunctions.AssetLease.OnServerInvoke
	local ret = remoteFunctions.AssetReturn.OnServerInvoke
	local bid = remoteFunctions.AuctionBid.OnServerInvoke
	local okFar, msgFar = lease(Far, "motorbike")
	check("Thuê khi đứng xa Trụ sở bị từ chối", not okFar)
	eq("Thông báo quá xa Trụ sở", msgFar, Config.Text.TooFarFromAura)
	eq("Đứng xa: không trừ tiền", dFar.Money, 5000)
	local okBidFar, msgBidFar = bid(Far, 100000)
	check("Đặt giá khi đứng xa bị từ chối", not okBidFar)
	eq("Đặt giá xa: thông báo quá xa", msgBidFar, Config.Text.TooFarFromAura)
	local okBad, msgBad = lease(Far, 123)
	eq("Tham số sai kiểu: không hợp lệ", msgBad, Config.Text.InvalidRequest)
	check("Tham số sai kiểu bị từ chối", not okBad)
	local Near, dNear = loadNew(951, "Near", Vector3.new(60, 3, 50), 5000)
	local okNear, msgNear = lease(Near, "motorbike")
	check("Thuê khi đứng gần Trụ sở", okNear, msgNear)
	eq("Đứng gần: trừ giá thuê", dNear.Money, 5000 - Config.Assets.motorbike.Price)
	local okRet, msgRet = ret(Near, "motorbike")
	check("Trả khi đứng gần Trụ sở", okRet, msgRet)
	local okSpam = true
	for _ = 1, 6 do
		local ok2, msg2 = lease(Near, "nonexistent")
		if msg2 == Config.Text.TooFast then okSpam = false end
		local _ = ok2
	end
	check("Gọi dồn dập bị rate-limit", not okSpam)
	taggedInstances[Config.Tags.Aura] = nil
end

-- ═══════════════ 12. ProfileStore: khởi tạo lỗi, khóa phiên ═══════════════
do
	eq("AUTO_SAVE_PERIOD lấy từ Config", FakeProfileStore.Constants.AUTO_SAVE_PERIOD, Config.Data.AutosaveSeconds)
	eq("Store tên v2", Config.Data.StoreName, "EqualSocial_PlayerData_v2")

	-- ProfileStore.New ném lỗi: Init không làm dừng boot, người chơi bị kick thay vì chơi bằng dữ liệu rỗng
	psNewFail = true
	local fresh = loadFresh("server/Services/DataService")
	local okInit = pcall(function() fresh:Init(svc) end)
	psNewFail = false
	check("Init không ném lỗi khi ProfileStore.New lỗi", okInit)
	local I = newPlayer(21, "Ivy")
	fresh:_load(I)
	check("Không có store: kick", I._kicked == Config.Text.DataLoadFailed)
	check("Không có store: không có dữ liệu", fresh:Get(I) == nil)

	-- Server khác đang giữ khóa (chưa nhả sau thời gian chờ): kick, không đọc/ghi dữ liệu
	storeData["u_980"] = { Money = 999, Aura = { LastCycle = 0, Escrow = { AuctionId = "x", AssetId = "villa", Amount = 500 } } }
	psLocks["u_980"] = "other-server"
	local K = newPlayer(980, "Kim")
	svc.Data:_load(K)
	eq("Khóa ở server khác: kick", K._kicked, Config.Text.DataLoadFailed)
	check("Khóa ở server khác: không có dữ liệu", svc.Data:Get(K) == nil)
	eq("Khóa ở server khác: tiền khóa KHÔNG bị hoàn lần hai", storeData["u_980"].Money, 999)
	check("Khóa ở server khác: escrow còn nguyên", storeData["u_980"].Aura.Escrow ~= nil)
	eq("Khóa ở server khác: khóa không bị đổi", psLocks["u_980"], "other-server")
	psLocks["u_980"] = nil

	-- Mở phiên bình thường: giữ khóa, gắn UserId; rời game thì lưu và nhả khóa
	local L = newPlayer(981, "Lan")
	svc.Data:_load(L)
	check("Mở phiên: có dữ liệu", svc.Data:Get(L) ~= nil)
	eq("Mở phiên: giữ khóa", psLocks["u_981"], fakeGame.JobId)
	eq("Mở phiên: gắn UserId", psUserIds["u_981"], 981)
	svc.Data:Get(L).Money = 4321
	svc.Data:_release(L)
	check("Rời game: nhả khóa", psLocks["u_981"] == nil)
	eq("Rời game: đã lưu", storeData["u_981"].Money, 4321)
	check("Rời game: không kick", L._kicked == nil)

	-- Server khác giành phiên khi đang chơi: gỡ dữ liệu ngay và kick
	local M = newPlayer(982, "Minh")
	svc.Data:_load(M)
	check("Trước khi bị giành: có dữ liệu", svc.Data:Get(M) ~= nil)
	psActive["u_982"]._steal()
	check("Bị giành phiên: gỡ dữ liệu", svc.Data:Get(M) == nil)
	eq("Bị giành phiên: kick tiếng Việt", M._kicked, Config.Text.DataSessionEnded)
	psLocks["u_982"] = nil

	-- Người chơi thoát trong lúc chờ mở phiên: không kick, không giữ khóa
	local N = newPlayer(983, "Nam")
	N.Parent = nil
	svc.Data:_load(N)
	check("Thoát khi đang tải: không kick", N._kicked == nil)
	check("Thoát khi đang tải: không giữ khóa", psLocks["u_983"] == nil)
	check("Thoát khi đang tải: không có dữ liệu", svc.Data:Get(N) == nil)

	-- Tải hai lần liên tiếp cùng người chơi: lần sau bỏ qua (không mở phiên thứ hai)
	local O = newPlayer(984, "Oanh")
	svc.Data:_load(O)
	local first = svc.Data:Get(O)
	svc.Data:_load(O)
	check("Tải lần hai: giữ nguyên dữ liệu", svc.Data:Get(O) == first)
	check("Tải lần hai: không kick", O._kicked == nil)
end

-- ═══════════════ 28. Cooldown trạm được lưu và làm sạch ═══════════════
do
	storeData["u_985"] = { Money = 100, StationUsed = { castle = 1, bed = "x", bench = os.time() } }
	local P = newPlayer(985, "Phuc")
	svc.Data:_load(P)
	local dP = svc.Data:Get(P)
	check("Bỏ trạm không còn trong Config", dP.StationUsed.castle == nil)
	check("Bỏ mốc thời gian hỏng", dP.StationUsed.bed == nil)
	check("Giữ mốc hợp lệ", dP.StationUsed.bench ~= nil)
	check("Vào lại vẫn còn cooldown ghế", svc.Stations:GetRemaining(P, "bench") > 0)
	eq("Giường dùng được (mốc hỏng đã bỏ)", svc.Stations:GetRemaining(P, "bed"), 0)
	svc.Data:_release(P)
	check("Lưu mốc dùng trạm", storeData["u_985"].StationUsed.bench ~= nil)
end

-- ═══════════════ 29. Season: danh hiệu, sang mùa, giữ lịch sử ═══════════════
do
	local SeasonUtil = fakeRequire(nodes["server/Util/Season"])
	local rec = { SeasonId = 0, Name = "Mùa 0", Money = 1, PeakNetWorth = 60000, Rating = 1320, Wins = 8, Losses = 3, Draws = 0, Titles = {} }
	local titles = SeasonUtil.TitlesFor(rec)
	eq("Danh hiệu: đủ 4 mức", #titles, 4)
	eq("Danh hiệu kèm tên mùa", titles[1], "Nhà vô địch đấu trường · Mùa 0")
	rec.Wins, rec.Losses = 2, 1
	local fewMatches = SeasonUtil.TitlesFor(rec)
	eq("Ít trận: không có danh hiệu PvP", #fewMatches, 2)
	eq("Ít trận: vẫn có danh hiệu tài sản", fewMatches[1], "Đại gia · Mùa 0")

	storeData["u_990"] = {
		SeasonId = 0, Money = 5000, PeakNetWorth = 60000,
		Pvp = { Rating = 1320, Wins = 8, Losses = 3, Draws = 0 },
		Owned = { sunglasses = true }, Assets = { car = { LeasedAt = 1, Missed = 0 } },
		Aura = { LastCycle = 1, Escrow = { AuctionId = "old", AssetId = "villa", Amount = 900 } },
		Skills = { Strength = { Level = 5, XP = 1 } }, StationUsed = { bed = os.time() },
		History = {}, Titles = { "Danh hiệu cũ" },
	}
	local Q = newPlayer(990, "Quan")
	svc.Data:_load(Q)
	local dQ = svc.Data:Get(Q)
	eq("Sang mùa: tiền về vạch xuất phát", dQ.Money, Config.Economy.StartingMoney)
	check("Sang mùa: tiền khóa mùa cũ KHÔNG được hoàn", dQ.Aura.Escrow == nil and dQ.Money == Config.Economy.StartingMoney)
	check("Sang mùa: đồ cửa hàng reset", next(dQ.Owned) == nil)
	check("Sang mùa: tài sản thuê reset", next(dQ.Assets) == nil)
	check("Sang mùa: cooldown trạm reset", next(dQ.StationUsed) == nil)
	eq("Sang mùa: kỹ năng reset", dQ.Skills.Strength.Level, 0)
	eq("Sang mùa: điểm PvP reset", dQ.Pvp.Rating, Config.Pvp.StartRating)
	eq("Sang mùa: đánh dấu mùa hiện tại", dQ.SeasonId, Config.Season.Id)
	eq("Sang mùa: lịch sử có 1 mùa", #dQ.History, 1)
	eq("Lịch sử: mùa cũ", dQ.History[1].SeasonId, 0)
	eq("Lịch sử: tài sản đỉnh", dQ.History[1].PeakNetWorth, 60000)
	eq("Lịch sử: điểm PvP", dQ.History[1].Rating, 1320)
	eq("Giữ danh hiệu cũ + thêm 4 mới", #dQ.Titles, 5)
	eq("Danh hiệu cũ còn nguyên", dQ.Titles[1], "Danh hiệu cũ")
	local taken = svc.Data:TakeRollover(Q)
	check("TakeRollover trả hồ sơ mùa vừa lưu", taken ~= nil and taken.SeasonId == 0)
	check("TakeRollover chỉ trả một lần", svc.Data:TakeRollover(Q) == nil)
	local snapQ = svc.Replication:BuildSnapshot(Q)
	eq("Snapshot: tên mùa", snapQ.Season.Name, Config.Season.Name)
	eq("Snapshot: danh hiệu mới nhất", snapQ.Season.Title, dQ.Titles[#dQ.Titles])
	svc.Data:_release(Q)

	-- Dữ liệu trước v0.4 (không có SeasonId): KHÔNG bị reset, chỉ được bổ sung trường mới
	storeData["u_991"] = { Money = 777, Skills = { Strength = { Level = 4, XP = 2 } } }
	local R = newPlayer(991, "Rin")
	svc.Data:_load(R)
	local dR = svc.Data:Get(R)
	eq("Dữ liệu cũ: giữ tiền", dR.Money, 777)
	eq("Dữ liệu cũ: giữ kỹ năng", dR.Skills.Strength.Level, 4)
	eq("Dữ liệu cũ: nhận mùa hiện tại", dR.SeasonId, Config.Season.Id)
	check("Dữ liệu cũ: không có hồ sơ sang mùa", svc.Data:TakeRollover(R) == nil)
	-- Tài sản ròng cao nhất được cập nhật khi tính tài sản ròng
	dR.Money = 4321
	svc.Leaderboard:GetNetWorth(R)
	eq("PeakNetWorth tăng theo tài sản ròng", dR.PeakNetWorth, 4321)
	dR.Money = 100
	svc.Leaderboard:GetNetWorth(R)
	eq("PeakNetWorth không giảm", dR.PeakNetWorth, 4321)
	svc.Data:_release(R)

	-- Lịch sử bị giới hạn
	local hist = {}
	for i = 1, Config.Season.HistorySize do hist[i] = { SeasonId = -i, Name = "x", Money = 0, PeakNetWorth = 0, Rating = 1000, Wins = 0, Losses = 0, Draws = 0, Titles = {} } end
	storeData["u_992"] = { SeasonId = 0, History = hist }
	local S2 = newPlayer(992, "Son")
	svc.Data:_load(S2)
	eq("Lịch sử không vượt HistorySize", #svc.Data:Get(S2).History, Config.Season.HistorySize)
	eq("Lịch sử: mùa mới nhất ở cuối", svc.Data:Get(S2).History[Config.Season.HistorySize].SeasonId, 0)
	svc.Data:_release(S2)
end

-- ═══════════════ 30. Đấu trường PvP ═══════════════
do
	local Pvp = svc.Pvp
	eq("Sát thương PvP Lv0", Pvp:GetDamage(0), 10)
	eq("Sát thương PvP Lv20 (x1,6)", Pvp:GetDamage(20), 16)
	eq("Elo ngang điểm thắng +16", Pvp:RatingDelta(1000, 1000, 1), 16)
	eq("Elo ngang điểm thua -16", Pvp:RatingDelta(1000, 1000, 0), -16)
	eq("Elo ngang điểm hòa 0", Pvp:RatingDelta(1000, 1000, 0.5), 0)
	eq("Elo thắng người mạnh hơn 400 điểm +29", Pvp:RatingDelta(1000, 1400, 1), 29)

	-- Đấu trường giả: hai bục ở x = ±14 quanh (0, 0, -125), quầy ở z = -89
	local center = Vector3.new(0, 0, -125)
	taggedInstances[Config.Tags.ArenaPad] = {
		fakeBasePart(center + Vector3.new(-14, 0, 0), Vector3.new(6, 1, 6), { [Config.Attributes.ArenaPad] = 1 }),
		fakeBasePart(center + Vector3.new(14, 0, 0), Vector3.new(6, 1, 6), { [Config.Attributes.ArenaPad] = 2 }),
	}
	local realSpawn = task.spawn
	task.spawn = function(f, ...) if select("#", ...) > 0 then realSpawn(f, ...) end end
	Pvp:Start()
	task.spawn = realSpawn
	-- Quầy gắn tag SAU Start: Instance giả không tạo được ProximityPrompt thật
	taggedInstances[Config.Tags.Arena] = { fakeBasePart(center + Vector3.new(0, 3.5, 36), Vector3.new(10, 7, 6), {}) }

	local P1, d1, r1 = loadNew(993, "Mai", center, 100)
	local P2, d2, r2 = loadNew(994, "Long", center, 100)
	local P3, d3 = loadNew(995, "Tired", center, 100)
	d3.Stats.Energy = 5
	Pvp:ToggleQueue(P3)
	check("Mệt: không vào được hàng chờ", not Pvp:IsQueued(P3))
	check("Mệt: có thông báo", string.find(lastNotif(P3), "Năng lượng", 1, true) ~= nil)
	Pvp:ToggleQueue(P1)
	check("Vào hàng chờ", Pvp:IsQueued(P1))
	eq("Trạng thái: queue", Pvp:GetState(P1).State, "queue")
	Pvp:ToggleQueue(P1)
	check("Nhấn lần nữa: rời hàng chờ", not Pvp:IsQueued(P1))
	Pvp:ToggleQueue(P1)
	Pvp:ToggleQueue(P2)
	Pvp:_matchmake()
	local match = Pvp:GetMatch(P1)
	check("Ghép cặp hai người", match ~= nil and Pvp:GetMatch(P2) == match)
	check("Ghép xong: rời hàng chờ", not Pvp:IsQueued(P1) and not Pvp:IsQueued(P2))
	eq("Pha đếm ngược", match.Phase, "countdown")
	check("Dịch chuyển lên bục", #P1.Character._pivots >= 1 and #P2.Character._pivots >= 1)
	Pvp:ToggleQueue(P1)
	check("Đang đấu: không vào hàng chờ", not Pvp:IsQueued(P1))

	r1.Position, r2.Position = center + Vector3.new(-3, 0, 0), center + Vector3.new(3, 0, 0)
	Pvp:Attack(P1)
	eq("Đếm ngược: chưa đánh được", match.HP[P2], Config.Pvp.MaxHP)
	Pvp:_tick(match.StartsAt)
	eq("Hết đếm ngược: vào pha đánh", match.Phase, "fight")
	Pvp:Attack(P1)
	eq("Đòn đầu: -10 máu", match.HP[P2], 90)
	Pvp:Attack(P1)
	eq("Đánh dồn dập: bị chặn", match.HP[P2], 90)
	match.LastAttack[P1] = nil
	r2.Position = center + Vector3.new(14, 0, 0)
	Pvp:Attack(P1)
	eq("Ngoài tầm đánh: không trúng", match.HP[P2], 90)
	r2.Position = center + Vector3.new(3, 0, 0)
	local outsider = loadNew(996, "Ngoai", center, 100)
	Pvp:Attack(outsider)
	eq("Người ngoài trận không đánh được", match.HP[P2], 90)
	local st = Pvp:GetState(P2)
	eq("Trạng thái gửi client: máu mình", st.MyHP, 90)
	eq("Trạng thái gửi client: máu đối thủ", st.OpponentHP, 100)
	eq("Trạng thái gửi client: tên đối thủ", st.OpponentName, "Mai")

	-- Hạ gục
	local energyBefore = d1.Stats.Energy
	local xpBefore = d1.Skills.Strength.XP + d1.Skills.Strength.Level * 1000
	match.HP[P2] = 5
	match.LastAttack[P1] = nil
	Pvp:Attack(P1)
	eq("Hạ gục: trận kết thúc", match.Phase, "ended")
	check("Hạ gục: gỡ trận", Pvp:GetMatch(P1) == nil and Pvp:GetMatch(P2) == nil)
	eq("Thắng: +16 điểm", d1.Pvp.Rating, 1016)
	eq("Thua: -16 điểm", d2.Pvp.Rating, 984)
	eq("Thắng: +1 trận thắng", d1.Pvp.Wins, 1)
	eq("Thua: +1 trận thua", d2.Pvp.Losses, 1)
	near("Chi phí Năng lượng sau trận", d1.Stats.Energy, energyBefore + Config.Pvp.StatDelta.Energy)
	check("Thắng: nhận XP Sức mạnh", d1.Skills.Strength.XP + d1.Skills.Strength.Level * 1000 > xpBefore)
	eq("Không đụng tới tiền", d1.Money, 100)
	check("Thông báo thắng có điểm", string.find(lastNotif(P1), "+16", 1, true) ~= nil)
	check("Thông báo thua có điểm", string.find(lastNotif(P2), "-16", 1, true) ~= nil)
	eq("Sau trận: idle", Pvp:GetState(P1).State, "idle")

	local function newMatch()
		Pvp:_startMatch(P1, P2, center + Vector3.new(-14, 0, 0), center + Vector3.new(14, 0, 0), 0)
		local m = Pvp:GetMatch(P1)
		Pvp:_tick(m.StartsAt)
		r1.Position, r2.Position = center + Vector3.new(-3, 0, 0), center + Vector3.new(3, 0, 0)
		return m
	end
	-- Ra khỏi vùng đấu
	local m2 = newMatch()
	r2.Position = center + Vector3.new(Config.Pvp.ZoneRadius + 5, 0, 0)
	Pvp:_tick(m2.StartsAt + 1)
	eq("Ra khỏi sàn: thua", d2.Pvp.Losses, 2)
	check("Ra khỏi sàn: thông báo lý do", string.find(lastNotif(P2), "ra khỏi sàn đấu", 1, true) ~= nil)
	-- Hết giờ: nhiều máu hơn thắng
	local m3 = newMatch()
	m3.HP[P1] = 40
	Pvp:_tick(m3.EndsAt)
	eq("Hết giờ: người nhiều máu hơn thắng", d2.Pvp.Wins, 1)
	-- Hết giờ bằng máu: hòa
	local m4 = newMatch()
	Pvp:_tick(m4.EndsAt)
	eq("Hết giờ bằng máu: hòa", d1.Pvp.Draws, 1)
	eq("Hòa: cả hai +1 hòa", d2.Pvp.Draws, 1)
	-- Nhân vật chết giữa trận: xử thua
	local m5 = newMatch()
	P2.Character:FindFirstChildOfClass("Humanoid").Health = 0
	Pvp:_tick(m5.StartsAt + 1)
	eq("Chết giữa trận: thua", d2.Pvp.Losses, 3)
	P2.Character:FindFirstChildOfClass("Humanoid").Health = 100
	-- Thoát game giữa trận: bị xử thua TRƯỚC khi dữ liệu được lưu
	newMatch()
	local lossesBefore = d2.Pvp.Losses
	svc.Data:_release(P2)
	eq("Thoát giữa trận: dữ liệu đã lưu có thêm trận thua", storeData["u_994"].Pvp.Losses, lossesBefore + 1)
	check("Thoát giữa trận: đối thủ được tính thắng", d1.Pvp.Wins >= 2)
	check("Thoát giữa trận: gỡ trận", Pvp:GetMatch(P1) == nil)
	-- Rời hàng chờ khi thoát game
	Pvp:ToggleQueue(P1)
	svc.Data:_release(P1)
	check("Thoát game: rời hàng chờ", not Pvp:IsQueued(P1))
	-- RemoteEvent: kẻ gian gọi dồn dập vẫn bị rate-limit, không lỗi
	local okSpam = pcall(function()
		for _ = 1, 30 do remoteEvents.PvpAttack.OnServerEvent:Fire(outsider) end
	end)
	check("PvpAttack dồn dập không gây lỗi", okSpam)

	-- Ghép cặp theo điểm: khoảng chênh cho phép nới dần theo thời gian chờ
	eq("Khoảng chênh lúc mới vào", Pvp:GetAllowedGap(0), Config.Pvp.MatchGapBase)
	eq("Khoảng chênh sau 30 giây", Pvp:GetAllowedGap(30), Config.Pvp.MatchGapBase + 30 * Config.Pvp.MatchGapPerSecond)
	-- Trận vừa mở đang ở pha đếm ngược: một lần _tick chuyển sang pha đánh, lần sau mới hết giờ
	local function endMatch(m) Pvp:_tick(m.StartsAt) Pvp:_tick(m.EndsAt) end
	local savedTime = serverTime
	serverTime = 5000
	local G1, g1 = loadNew(997, "Gioi", center, 100)
	local G2, g2 = loadNew(998, "Moi", center, 100)
	local G3, g3 = loadNew(999, "Kha", center, 100)
	g1.Pvp.Rating, g2.Pvp.Rating, g3.Pvp.Rating = 1400, 1000, 1350
	Pvp:ToggleQueue(G1)
	Pvp:ToggleQueue(G2)
	Pvp:_matchmake()
	check("Chênh 400 điểm, mới vào: chưa ghép", Pvp:GetMatch(G1) == nil and Pvp:IsQueued(G1) and Pvp:IsQueued(G2))
	Pvp:ToggleQueue(G3)
	Pvp:_matchmake()
	check("Ghép người gần điểm nhất (1400 gặp 1350)", Pvp:GetMatch(G1) ~= nil and Pvp:GetMatch(G1) == Pvp:GetMatch(G3))
	check("Người chênh xa vẫn chờ", Pvp:IsQueued(G2) and Pvp:GetMatch(G2) == nil)
	-- Một đấu trường, một trận mỗi lúc: người thứ tư vào cũng không mở trận thứ hai
	local G4 = loadNew(1000, "Tu", center, 100)
	Pvp:ToggleQueue(G4)
	Pvp:_matchmake()
	check("Đang có trận: không mở trận thứ hai", Pvp:IsArenaBusy() and Pvp:GetMatch(G4) == nil and Pvp:IsQueued(G4))
	-- Kết thúc trận đang diễn ra rồi ghép tiếp: G2 (1000) và G4 (1000) ngang điểm
	endMatch(Pvp:GetMatch(G1))
	Pvp:_matchmake()
	check("Trận xong: ghép cặp tiếp theo", Pvp:GetMatch(G2) ~= nil and Pvp:GetMatch(G2) == Pvp:GetMatch(G4))
	endMatch(Pvp:GetMatch(G2))
	-- Chờ đủ lâu thì chênh lệch lớn vẫn được ghép
	g2.Pvp.Rating = 1000
	g1.Pvp.Rating = 1400
	Pvp:ToggleQueue(G1)
	Pvp:ToggleQueue(G2)
	Pvp:_matchmake()
	check("Vừa vào lại: chênh 400 chưa ghép", Pvp:GetMatch(G1) == nil)
	serverTime += 30
	Pvp:_matchmake()
	check("Chờ 30 giây: chênh 400 được ghép", Pvp:GetMatch(G1) ~= nil and Pvp:GetMatch(G1) == Pvp:GetMatch(G2))
	endMatch(Pvp:GetMatch(G1))
	serverTime = savedTime
	taggedInstances[Config.Tags.ArenaPad], taggedInstances[Config.Tags.Arena] = nil, nil
end

-- ═══════════════ 31. Hồ sơ (GetProfile) ═══════════════
do
	local realSpawn = task.spawn
	task.spawn = function(f, ...) if select("#", ...) > 0 then realSpawn(f, ...) end end
	svc.Season:Start()
	task.spawn = realSpawn
	local getProfile = remoteFunctions.GetProfile.OnServerInvoke
	storeData["u_1001"] = {
		SeasonId = Config.Season.Id, Money = 300, PeakNetWorth = 12000,
		Pvp = { Rating = 1088, Wins = 5, Losses = 2, Draws = 1 },
		Titles = { "Đấu sĩ · Mùa 0" },
		History = { { SeasonId = 0, Name = "Mùa 0", Money = 900, PeakNetWorth = 60000, Rating = 1200, Wins = 6, Losses = 1, Draws = 0, Titles = { "Đấu sĩ · Mùa 0" } } },
	}
	local T1 = newPlayer(1001, "Tam")
	svc.Data:_load(T1)
	local view = getProfile(T1)
	check("Hồ sơ: có dữ liệu", view ~= nil)
	eq("Hồ sơ: tên mùa", view.SeasonName, Config.Season.Name)
	eq("Hồ sơ: điểm PvP", view.Pvp.Rating, 1088)
	eq("Hồ sơ: số trận thắng", view.Pvp.Wins, 5)
	eq("Hồ sơ: tài sản đỉnh", view.PeakNetWorth, 12000)
	eq("Hồ sơ: danh hiệu", view.Titles[1], "Đấu sĩ · Mùa 0")
	eq("Hồ sơ: lịch sử", #view.History, 1)
	eq("Hồ sơ: lịch sử mùa 0", view.History[1].PeakNetWorth, 60000)
	-- Bản sao: sửa kết quả không đụng tới dữ liệu thật
	table.insert(view.Titles, "giả mạo")
	view.History[1].Rating = 9999
	eq("Hồ sơ là bản sao (danh hiệu)", #svc.Data:Get(T1).Titles, 1)
	eq("Hồ sơ là bản sao (lịch sử)", svc.Data:Get(T1).History[1].Rating, 1200)
	-- Người chưa có dữ liệu: nil, không lỗi
	local T2 = newPlayer(1002, "ChuaTai")
	check("Chưa tải dữ liệu: nil", getProfile(T2) == nil)
	-- Rate-limit: 3 lần / 10 giây
	getProfile(T1)
	getProfile(T1)
	check("Gọi lần thứ 4 trong 10 giây: nil", getProfile(T1) == nil)
	svc.Data:_release(T1)
end

print(("KẾT QUẢ: %d đạt, %d lỗi"):format(passed, failed))
if failed > 0 then error("có kiểm tra thất bại") end
