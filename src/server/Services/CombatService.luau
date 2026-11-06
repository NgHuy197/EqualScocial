--!strict
--[[
	CombatService — đánh quái kiếm tiền ở Bãi luyện tập.

	Điểm xuất hiện: instance có tag Config.Tags.MonsterSpawn + attribute MonsterId (trỏ tới Config.Monsters).
	Mỗi điểm giữ một quái; quái bị hạ thì hồi sinh sau RespawnSeconds.

	Luồng đánh:
	  * Người chơi nhấn E vào quái (ProximityPrompt qua Util/Prompts) => _attack.
	    Sát thương = round(BaseDamage * (1 + 0.15 * level Sức mạnh)); chu kỳ đánh phụ thuộc Năng lượng.
	    Server kiểm tra tầm đánh và chu kỳ riêng (ngoài cooldown của prompt), không tin client.
	  * Quái đứng yên, mỗi MonsterTickSeconds tìm người chơi gần nhất trong tầm rồi đánh (Humanoid:TakeDamage).
	    Máu trong trận là máu Humanoid, TÁCH RIÊNG chỉ số Sức khỏe (không gây kiệt sức).
	  * Hạ quái: chia thưởng cho người đã gây >= MinContribution máu tối đa (càng đông càng giảm),
	    tiền chịu trần HourlyMoneyCap theo cửa sổ lưu trong dữ liệu người chơi, XP luôn được nhận.
	  * Thua trận: chết trong DefeatWindowSeconds sau khi bị quái đánh => trả phí, hồi sinh ở Bệnh xá.
	Mọi tiền thưởng đều đi qua EconomyService (lý do "monster" / "defeat").
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local MonsterModel = require(script.Parent.Parent.Util.MonsterModel)
local Prompts = require(script.Parent.Parent.Util.Prompts)
local Validate = require(script.Parent.Parent.Util.Validate)

type MonsterDef = Config.MonsterDef
type PlayerData = Types.PlayerData

type Slot = {
	Point: BasePart,
	MonsterId: string,
	Monster: Monster?,
	RespawnAt: number, -- os.clock() khi được phép hồi sinh
}

type Monster = {
	Id: string,
	Def: MonsterDef,
	Handle: MonsterModel.Handle,
	HP: number,
	Damage: { [Player]: number }, -- tổng sát thương mỗi người đã gây
	NextAttackAt: number, -- os.clock() quái được phép đánh lần kế
	Slot: Slot,
}

type Hit = {
	Time: number,
	Name: string,
}

local MONSTER_FOLDER = "Monsters"

local services: Types.Services = {}
local slots: { [Instance]: Slot } = {}
local monsters: { [Instance]: Monster } = {} -- model -> quái đang sống

local function weakPlayerMap(): any
	return setmetatable({}, { __mode = "k" })
end
local lastAttack: { [Player]: number } = weakPlayerMap()
local lastMonsterHit: { [Player]: Hit } = weakPlayerMap()
local defeated: { [Player]: boolean } = weakPlayerMap()

local CombatService = {}

-- ───────────────────────────── Công thức (tách riêng để dễ test) ─────────────────────────────

-- Tốc độ đánh: MinSpeedFactor khi Năng lượng 0, tăng tuyến tính tới 1 khi Năng lượng >= FullSpeedEnergy
local function attackSpeed(energy: number): number
	local cfg = Config.Combat
	local fraction = math.clamp(energy / cfg.FullSpeedEnergy, 0, 1)
	return cfg.MinSpeedFactor + (1 - cfg.MinSpeedFactor) * fraction
end

function CombatService:GetDamage(strengthLevel: number): number
	local cfg = Config.Combat
	return math.floor(cfg.BaseDamage * (1 + cfg.DamagePerStrengthLevel * strengthLevel) + 0.5)
end

function CombatService:GetAttackInterval(energy: number): number
	return Config.Combat.AttackInterval / attackSpeed(energy)
end

-- Tỉ lệ thưởng mỗi người nhận khi có `participants` người cùng hạ một quái
function CombatService:GetShare(participants: number): number
	local cfg = Config.Combat
	return math.max(cfg.MinShare, 1 - cfg.SharePenaltyPerExtraPlayer * (participants - 1))
end

-- Quái đang sống ứng với model (nil nếu model không phải quái hoặc quái đã bị gỡ)
function CombatService:GetMonster(model: Instance): Monster?
	return monsters[model]
end

-- ───────────────────────────── Tiện ích ─────────────────────────────

local function getLiveHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function getMonsterFolder(): Folder
	local existing = Workspace:FindFirstChild(MONSTER_FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = MONSTER_FOLDER
	folder.Parent = Workspace
	return folder
end

-- Gỡ quái khỏi thế giới và khỏi bảng theo dõi (đồng bộ, an toàn khi gọi nhiều lần)
local function removeMonster(monster: Monster)
	local model = monster.Handle.Model
	if monsters[model] ~= monster then
		return
	end
	monsters[model] = nil
	monster.Slot.Monster = nil
	model:Destroy()
end

-- ───────────────────────────── Vòng đời ─────────────────────────────

local function validateConfig()
	for monsterId, def in Config.Monsters do
		if not Validate.isId(monsterId) then
			warn(`[CombatService] Id quái không hợp lệ: {monsterId}`)
		end
		for statId in def.StatDelta do
			if not Config.Stats.Defs[statId] then
				warn(
					`[CombatService] Quái '{monsterId}' có chi phí cho chỉ số không tồn tại: {statId}`
				)
			end
		end
	end
	if not Config.Skills.Defs[Config.Combat.Skill] then
		warn(`[CombatService] Combat.Skill không tồn tại: {Config.Combat.Skill}`)
	end
end

function CombatService:Init(allServices: Types.Services)
	services = allServices
	validateConfig()
end

function CombatService:Start()
	-- Prompt "Đánh" gắn cho quái đang sống (quái được gắn tag lúc spawn)
	Prompts.BindTag(Config.Tags.Monster, function(inst: Instance): Prompts.Spec?
		local monster = self:GetMonster(inst)
		if not monster then
			return nil
		end
		return {
			ActionText = Config.Text.AttackAction,
			ObjectText = monster.Def.Name,
			HoldDuration = 0,
			MaxActivationDistance = Config.Combat.PlayerAttackRange,
			Cooldown = Config.Combat.MinAttackCooldown,
			OnTriggered = function(player: Player)
				self:_attack(player, monster)
			end,
		}
	end)

	-- Điểm xuất hiện (hiện có và thêm sau này, ví dụ khi thay bằng map thật)
	CollectionService:GetInstanceAddedSignal(Config.Tags.MonsterSpawn):Connect(function(inst)
		self:_registerPoint(inst)
	end)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.MonsterSpawn):Connect(function(inst)
		self:_unregisterPoint(inst)
	end)
	for _, inst in CollectionService:GetTagged(Config.Tags.MonsterSpawn) do
		task.spawn(self._registerPoint, self, inst)
	end

	-- Thua trận: theo dõi nhân vật của từng người chơi
	Players.PlayerAdded:Connect(function(player: Player)
		self:_watchPlayer(player)
	end)
	for _, player in Players:GetPlayers() do
		self:_watchPlayer(player)
	end

	-- Vòng AI của quái (bọc pcall để một lỗi lặt vặt không làm dừng cả vòng)
	task.spawn(function()
		while true do
			task.wait(Config.Combat.MonsterTickSeconds)
			local ok, err = pcall(function()
				self:_tickMonsters()
			end)
			if not ok then
				warn(`[CombatService] Lỗi vòng AI quái: {tostring(err)}`)
			end
		end
	end)
end

-- ───────────────────────────── Điểm xuất hiện và hồi sinh ─────────────────────────────

function CombatService:_registerPoint(inst: Instance)
	if slots[inst] or not inst:IsDescendantOf(Workspace) then
		return
	end
	if not inst:IsA("BasePart") then
		warn(
			`[CombatService] {inst:GetFullName()} có tag MonsterSpawn nhưng không phải BasePart`
		)
		return
	end
	local monsterId = inst:GetAttribute(Config.Attributes.Monster)
	if type(monsterId) ~= "string" or not Config.Monsters[monsterId] then
		warn(
			`[CombatService] {inst:GetFullName()} có attribute {Config.Attributes.Monster} không hợp lệ`
		)
		return
	end
	local slot: Slot = { Point = inst, MonsterId = monsterId, Monster = nil, RespawnAt = 0 }
	slots[inst] = slot
	self:_spawn(slot)
end

function CombatService:_unregisterPoint(inst: Instance)
	local slot = slots[inst]
	if not slot then
		return
	end
	slots[inst] = nil
	local monster = slot.Monster
	if monster then
		removeMonster(monster)
	end
end

function CombatService:_spawn(slot: Slot)
	local def = Config.Monsters[slot.MonsterId]
	if not def or slot.Monster then
		return
	end
	-- Quái đứng trên mặt trên của điểm xuất hiện
	local ground = slot.Point.Position + Vector3.new(0, slot.Point.Size.Y / 2, 0)
	local handle = MonsterModel.Build(slot.MonsterId, def, ground, getMonsterFolder())
	local monster: Monster = {
		Id = slot.MonsterId,
		Def = def,
		Handle = handle,
		HP = def.MaxHP,
		Damage = {},
		NextAttackAt = 0,
		Slot = slot,
	}
	monsters[handle.Model] = monster
	slot.Monster = monster
	-- Gắn tag SAU khi đã đăng ký: prompt "Đánh" được tạo qua Prompts.BindTag
	CollectionService:AddTag(handle.Model, Config.Tags.Monster)
end

function CombatService:_tickMonsters()
	local now = os.clock()
	for _, slot in slots do
		local monster = slot.Monster
		if monster then
			self:_monsterAct(monster, now)
		elseif now >= slot.RespawnAt then
			self:_spawn(slot)
		end
	end
end

-- Quái đánh người chơi gần nhất trong tầm (nếu đã hết thời gian chờ giữa hai đòn)
function CombatService:_monsterAct(monster: Monster, now: number)
	if now < monster.NextAttackAt then
		return
	end
	local origin = monster.Handle.Body.Position
	local target: Player? = nil
	local targetDistance = monster.Def.AttackRange
	for _, player in Players:GetPlayers() do
		local position = Validate.getRootPosition(player)
		if position then
			local distance = (position - origin).Magnitude
			if distance <= targetDistance then
				target = player
				targetDistance = distance
			end
		end
	end
	if not target then
		return
	end
	local humanoid = getLiveHumanoid(target)
	if not humanoid then
		return
	end
	humanoid:TakeDamage(monster.Def.Damage)
	lastMonsterHit[target] = { Time = now, Name = monster.Def.Name }
	monster.NextAttackAt = now + monster.Def.AttackInterval
end

-- ───────────────────────────── Người chơi đánh quái ─────────────────────────────

function CombatService:_attack(player: Player, monster: Monster)
	-- Quái đã bị hạ hoặc đã bị gỡ (request đến muộn)
	if monster.HP <= 0 or monsters[monster.Handle.Model] ~= monster then
		return
	end
	if not services.Data:Get(player) then
		return
	end

	-- Prompt đã kiểm tra khoảng cách; kiểm tra lại chặt hơn bằng chính tầm đánh (dung sai nhỏ)
	local reach = Config.Combat.PlayerAttackRange + Config.Combat.AttackRangeTolerance
	if not Validate.isWithin(player, monster.Handle.Body.Position, reach) then
		return
	end

	-- Chu kỳ đánh phụ thuộc Năng lượng; nhân CooldownFactor làm dung sai cho độ trễ mạng
	local energy = services.Stats:Get(player, "Energy") or 0
	local now = os.clock()
	local last = lastAttack[player]
	local interval: number = self:GetAttackInterval(energy)
	if last and now - last < interval * Config.Prompts.CooldownFactor then
		return
	end
	lastAttack[player] = now

	local level: number = services.Skills:GetLevel(player, Config.Combat.Skill)
	local damage: number = self:GetDamage(level)
	local dealt = math.min(damage, monster.HP)
	monster.HP -= dealt
	monster.Damage[player] = (monster.Damage[player] or 0) + dealt
	MonsterModel.SetHealth(monster.Handle, monster.HP / monster.Def.MaxHP)

	if monster.HP <= 0 then
		self:_kill(monster)
	end
end

-- Quái bị hạ: gỡ quái trước (đồng bộ, không thể bị hạ hai lần) rồi chia thưởng
function CombatService:_kill(monster: Monster)
	local def = monster.Def
	local participants: { Player } = {}
	for player, damage in monster.Damage do
		if player.Parent == Players and damage >= def.MaxHP * Config.Combat.MinContribution then
			table.insert(participants, player)
		end
	end
	local share = self:GetShare(#participants)

	removeMonster(monster)
	monster.Slot.RespawnAt = os.clock() + def.RespawnSeconds

	for _, player in participants do
		self:_reward(player, def, share)
	end
end

-- Cộng tiền (chịu trần theo giờ) vào dữ liệu người chơi. Trả về số tiền thực nhận.
function CombatService:_payMoney(player: Player, data: PlayerData, intended: number): number
	local combat = data.Combat
	local nowUnix = os.time()
	if nowUnix - combat.WindowStart >= Config.Combat.CapWindowSeconds then
		combat.WindowStart = nowUnix -- mở cửa sổ mới
		combat.Earned = 0
	end
	local room = math.max(0, Config.Combat.HourlyMoneyCap - combat.Earned)
	local amount = math.min(intended, room)
	if amount <= 0 then
		return 0
	end
	local paid = services.Economy:Add(player, amount, Config.Reasons.Monster)
	combat.Earned += paid
	return paid
end

function CombatService:_reward(player: Player, def: MonsterDef, share: number)
	local data = services.Data:Get(player)
	if not data then
		return
	end
	local xp = math.max(1, math.floor(def.XPReward * share + 0.5))
	local intended = math.floor(def.Reward * share + 0.5)
	local paid = self:_payMoney(player, data, intended)

	services.Stats:Modify(player, def.StatDelta)
	services.Skills:AddXP(player, Config.Combat.Skill, xp)

	local skillDef = Config.Skills.Defs[Config.Combat.Skill]
	local skillName = if skillDef then skillDef.Name else Config.Combat.Skill
	if paid > 0 then
		services.Replication:Notify(
			player,
			string.format(Config.Text.MonsterKilled, def.Name, Format.money(paid), xp, skillName),
			"success"
		)
	else
		services.Replication:Notify(
			player,
			string.format(Config.Text.MonsterKilledCapped, def.Name, xp, skillName),
			"warning"
		)
	end
end

-- ───────────────────────────── Thua trận ─────────────────────────────

function CombatService:_watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(self._onCharacterAdded, self, player, character)
	end)
	local character = player.Character
	if character then
		task.spawn(self._onCharacterAdded, self, player, character)
	end
end

function CombatService:_onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			self:_onDeath(player)
		end)
	end
	-- Vừa thua trận: đưa tới Bệnh xá thay vì điểm hồi sinh thường
	if defeated[player] then
		defeated[player] = nil
		self:_sendToInfirmary(character)
	end
end

-- Chết trong DefeatWindowSeconds sau khi bị quái đánh => thua trận (không kiệt sức, không mất % tiền)
function CombatService:_onDeath(player: Player)
	local hit = lastMonsterHit[player]
	if not hit or os.clock() - hit.Time > Config.Combat.DefeatWindowSeconds then
		return
	end
	lastMonsterHit[player] = nil
	defeated[player] = true

	-- Phí chỉ thu tối đa bằng số tiền đang có (không bao giờ làm âm tiền)
	local fee = math.min(services.Economy:Get(player), Config.Combat.DefeatFee)
	if fee > 0 then
		services.Economy:TrySpend(player, fee, Config.Reasons.Defeat)
	end
	services.Replication:Notify(
		player,
		string.format(Config.Text.Defeated, hit.Name, Format.money(fee)),
		"warning"
	)
end

function CombatService:_sendToInfirmary(character: Model)
	for _, inst in CollectionService:GetTagged(Config.Tags.Infirmary) do
		local anchor = if inst:IsDescendantOf(Workspace) then Prompts.GetAnchor(inst) else nil
		if anchor then
			-- Engine đặt nhân vật vào điểm hồi sinh SAU khi sự kiện CharacterAdded chạy (lúc đó vị trí còn
			-- ở gốc toạ độ), nên phải đợi engine đặt xong rồi mới dịch chuyển, nếu không sẽ bị ghi đè.
			local root = character:WaitForChild("HumanoidRootPart", 5)
			if root and root:IsA("BasePart") then
				local deadline = os.clock() + Config.Combat.SpawnSettleSeconds
				while root.Position.Magnitude < 0.5 and os.clock() < deadline do
					task.wait()
				end
			end
			-- Xuất hiện ngay trước cửa Bệnh xá (phía -Z), cách mặt đất InfirmaryDropHeight studs
			local ground = anchor.Position
				- Vector3.new(0, anchor.Size.Y / 2, anchor.Size.Z / 2 + 4)
			character:PivotTo(
				CFrame.new(ground + Vector3.new(0, Config.World.InfirmaryDropHeight, 0))
			)
			return
		end
	end
end

return CombatService
