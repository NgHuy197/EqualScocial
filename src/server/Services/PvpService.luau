--!strict
--[[
	PvpService — Đấu trường 1v1 có luật (v0.4).

	  * Vào / rời hàng chờ: nhấn E ở quầy (tag Config.Tags.Arena). Cần dữ liệu đã tải, Năng lượng >=
	    Pvp.MinEnergy, không đang đấu. Ghép cặp theo thứ tự vào hàng chờ.
	  * Trận: dịch chuyển hai người lên hai bục (tag ArenaPad, attribute PadIndex 1/2), đếm ngược, rồi
	    đánh trong Pvp.MatchSeconds giây. Máu PvP là số RIÊNG trên server (Pvp.MaxHP), không đụng tới máu
	    nhân vật, nên thua trận không chết, không mất tiền.
	  * Tấn công: RemoteEvent PvpAttack (không tham số; mục tiêu luôn là đối thủ do server biết). Server
	    kiểm tra rate-limit, đang trong pha đánh, nhịp đánh (Pvp.AttackInterval) và khoảng cách thật.
	  * Luật kết thúc: hết máu (ko), hết giờ (nhiều máu hơn thắng, bằng thì hòa), ra khỏi vùng đấu
	    (zone), thoát game / nhân vật chết / mất nhân vật (left).
	  * Kết quả: điểm Elo theo mùa (Pvp.KFactor), XP Sức mạnh, chi phí chỉ số. KHÔNG có tiền cược hay quỹ
	    thưởng: Roblox cấm cờ bạc mô phỏng (xem GDD 8.1).
	  * Thoát game giữa trận vẫn bị xử thua: DataService:OnReleasing chạy trước khi dữ liệu bị gỡ.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Prompts = require(script.Parent.Parent.Util.Prompts)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validate = require(script.Parent.Parent.Util.Validate)

type PlayerData = Types.PlayerData

type Match = {
	A: Player,
	B: Player,
	HP: { [Player]: number },
	LastAttack: { [Player]: number },
	Phase: string, -- "countdown" | "fight" | "ended"
	StartsAt: number,
	EndsAt: number,
	Center: Vector3,
}

local PvpAttack = Remotes.Event("PvpAttack")
local PvpUpdate = Remotes.Event("PvpUpdate")

local services: Types.Services = {}
local queue: { Player } = {}
local matchOf: { [Player]: Match } = {}
local matches: { Match } = {}
local attackLimiter =
	RateLimiter.new(Config.RateLimits.PvpAttack.Calls, Config.RateLimits.PvpAttack.Window)

local PvpService = {}

-- Khai báo trước: dùng trong Start/Attack/_tick, định nghĩa ở mục "Trận đấu"
local finishMatch: (match: Match, winner: Player?, reason: string) -> ()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function opponentOf(match: Match, player: Player): Player
	return if match.A == player then match.B else match.A
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil and humanoid.Health > 0 and rootOf(player) ~= nil
end

local function teleport(player: Player, position: Vector3)
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(position))
	end
end

-- ───────────────────────────── Công thức (thuần, dùng cho test) ─────────────────────────────

-- Sát thương một đòn PvP theo level Sức mạnh
function PvpService:GetDamage(strengthLevel: number): number
	local pvp = Config.Pvp
	return math.floor(pvp.BaseDamage * (1 + pvp.DamagePerStrengthLevel * strengthLevel) + 0.5)
end

-- Điểm thay đổi của người có điểm `rating` gặp đối thủ `opponent`, kết quả score (1 thắng, 0.5 hòa,
-- 0 thua). Làm tròn tới số nguyên.
function PvpService:RatingDelta(rating: number, opponent: number, score: number): number
	local expected = 1 / (1 + 10 ^ ((opponent - rating) / 400))
	return math.floor(Config.Pvp.KFactor * (score - expected) + 0.5)
end

-- Bục xuất phát 1 và 2 (nil nếu map thiếu)
function PvpService:GetPads(): (Vector3?, Vector3?)
	local pads: { [number]: Vector3 } = {}
	for _, inst in CollectionService:GetTagged(Config.Tags.ArenaPad) do
		local index = inst:GetAttribute(Config.Attributes.ArenaPad)
		local anchor = if inst:IsDescendantOf(Workspace) then Prompts.GetAnchor(inst) else nil
		if anchor and (index == 1 or index == 2) then
			pads[index :: number] = anchor.Position
		end
	end
	return pads[1], pads[2]
end

-- Vị trí trả người chơi về sau trận: cạnh quầy hàng chờ gần nhất (nil nếu không có quầy)
function PvpService:GetReturnPosition(): Vector3?
	for _, inst in CollectionService:GetTagged(Config.Tags.Arena) do
		local anchor = if inst:IsDescendantOf(Workspace) then Prompts.GetAnchor(inst) else nil
		if anchor then
			return anchor.Position + Vector3.new(anchor.Size.X / 2 + 4, 4, 0)
		end
	end
	return nil
end

function PvpService:IsQueued(player: Player): boolean
	return table.find(queue, player) ~= nil
end

function PvpService:GetMatch(player: Player): Match?
	return matchOf[player]
end

-- Trạng thái đấu trường gửi cho client
function PvpService:GetState(player: Player): Types.PvpState
	local match = matchOf[player]
	if match and match.Phase ~= "ended" then
		local opponent = opponentOf(match, player)
		return {
			State = match.Phase,
			OpponentName = opponent.DisplayName,
			MyHP = match.HP[player],
			OpponentHP = match.HP[opponent],
			MaxHP = Config.Pvp.MaxHP,
			StartsAt = match.StartsAt,
			EndsAt = match.EndsAt,
		}
	end
	return { State = if self:IsQueued(player) then "queue" else "idle" }
end

function PvpService:_send(player: Player)
	if player.Parent == Players then
		PvpUpdate:FireClient(player, self:GetState(player))
	end
end

-- ───────────────────────────── Vòng đời service ─────────────────────────────

function PvpService:Init(allServices: Types.Services)
	services = allServices
	local pvp = Config.Pvp
	if pvp.MaxHP <= 0 or pvp.MatchSeconds <= 0 or pvp.KFactor <= 0 then
		warn("[PvpService] Config.Pvp có số không hợp lệ")
	end
end

function PvpService:Start()
	Prompts.BindTag(Config.Tags.Arena, function(_inst: Instance): Prompts.Spec?
		return {
			ActionText = Config.Text.ArenaPrompt,
			ObjectText = Config.Text.ArenaObject,
			HoldDuration = 0,
			Cooldown = 1,
			OnTriggered = function(player: Player)
				self:ToggleQueue(player)
			end,
		}
	end)

	PvpAttack.OnServerEvent:Connect(function(player: Player)
		if not Validate.isPlayer(player) or not attackLimiter:Allow(player) then
			return
		end
		local ok, err = pcall(function()
			self:Attack(player)
		end)
		if not ok then
			warn(`[PvpService] Lỗi xử lý đòn đánh: {tostring(err)}`)
		end
	end)

	-- Thoát game: rời hàng chờ; đang đấu thì xử thua TRƯỚC khi dữ liệu bị gỡ (để điểm được lưu)
	services.Data:OnReleasing(function(player: Player)
		self:_removeFromQueue(player)
		local match = matchOf[player]
		if match and match.Phase ~= "ended" then
			finishMatch(match, opponentOf(match, player), "left")
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self:_removeFromQueue(player) -- người chưa có dữ liệu không đi qua OnReleasing
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Pvp.MatchmakeSeconds)
			local ok, err = pcall(function()
				self:_matchmake()
			end)
			if not ok then
				warn(`[PvpService] Lỗi ghép cặp: {tostring(err)}`)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Pvp.TickSeconds)
			local ok, err = pcall(function()
				self:_tick(now())
			end)
			if not ok then
				warn(`[PvpService] Lỗi vòng trận đấu: {tostring(err)}`)
			end
		end
	end)
end

-- ───────────────────────────── Hàng chờ ─────────────────────────────

function PvpService:ToggleQueue(player: Player)
	if matchOf[player] then
		services.Replication:Notify(player, Config.Text.PvpBusy, "warning")
		return
	end
	if self:IsQueued(player) then
		self:_removeFromQueue(player)
		services.Replication:Notify(player, Config.Text.PvpLeft, "info")
		self:_send(player)
		return
	end
	local energy = services.Stats:Get(player, "Energy")
	if energy == nil then
		services.Replication:Notify(player, Config.Text.NoData, "warning")
		return
	end
	if energy < Config.Pvp.MinEnergy then
		services.Replication:Notify(
			player,
			string.format(Config.Text.PvpTooTired, Config.Pvp.MinEnergy),
			"warning"
		)
		return
	end
	local pad1, pad2 = self:GetPads()
	if not pad1 or not pad2 then
		services.Replication:Notify(player, Config.Text.PvpNoArena, "warning")
		return
	end
	table.insert(queue, player)
	services.Replication:Notify(player, string.format(Config.Text.PvpJoined, #queue), "info")
	self:_send(player)
end

function PvpService:_removeFromQueue(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
end

-- Người trong hàng chờ còn đủ điều kiện để bắt đầu trận không
local function canStart(player: Player): boolean
	return player.Parent == Players
		and services.Data:Get(player) ~= nil
		and matchOf[player] == nil
		and isAlive(player)
end

function PvpService:_matchmake()
	-- Bỏ người không còn đủ điều kiện (thoát, chưa có nhân vật...)
	for i = #queue, 1, -1 do
		if not canStart(queue[i]) then
			table.remove(queue, i)
		end
	end
	while #queue >= 2 do
		local pad1, pad2 = self:GetPads()
		if not pad1 or not pad2 then
			return
		end
		local a = table.remove(queue, 1) :: Player
		local b = table.remove(queue, 1) :: Player
		self:_startMatch(a, b, pad1, pad2, now())
	end
end

function PvpService:_startMatch(a: Player, b: Player, pad1: Vector3, pad2: Vector3, time: number)
	local pvp = Config.Pvp
	local startsAt = time + pvp.CountdownSeconds
	local match: Match = {
		A = a,
		B = b,
		HP = { [a] = pvp.MaxHP, [b] = pvp.MaxHP },
		LastAttack = {},
		Phase = "countdown",
		StartsAt = startsAt,
		EndsAt = startsAt + pvp.MatchSeconds,
		Center = (pad1 + pad2) / 2,
	}
	matchOf[a] = match
	matchOf[b] = match
	table.insert(matches, match)

	local up = Vector3.new(0, 4, 0)
	teleport(a, pad1 + up)
	teleport(b, pad2 + up)
	for _, player in { a, b } do
		local opponent = opponentOf(match, player)
		local data = services.Data:Get(opponent)
		local rating = if data then math.floor(data.Pvp.Rating + 0.5) else pvp.StartRating
		services.Replication:Notify(
			player,
			string.format(
				Config.Text.PvpMatchFound,
				opponent.DisplayName,
				rating,
				pvp.CountdownSeconds
			),
			"info"
		)
		self:_send(player)
	end
end

-- ───────────────────────────── Trận đấu ─────────────────────────────

-- Kết thúc trận: winner = nil nghĩa là hòa. Gỡ trận trước (đồng bộ) để không thể kết thúc hai lần.
finishMatch = function(match: Match, winner: Player?, reason: string)
	if match.Phase == "ended" then
		return
	end
	match.Phase = "ended"
	matchOf[match.A] = nil
	matchOf[match.B] = nil

	local pvp = Config.Pvp
	local dataA = services.Data:Get(match.A)
	local dataB = services.Data:Get(match.B)
	local ratingA = if dataA then dataA.Pvp.Rating else pvp.StartRating
	local ratingB = if dataB then dataB.Pvp.Rating else pvp.StartRating
	local reasonText = Config.Text.PvpReasons[reason] or reason

	for _, player in { match.A, match.B } do
		local data: PlayerData? = if player == match.A then dataA else dataB
		local opponent = opponentOf(match, player)
		local mine = if player == match.A then ratingA else ratingB
		local theirs = if player == match.A then ratingB else ratingA
		local score = if winner == nil then 0.5 elseif winner == player then 1 else 0
		local delta = PvpService:RatingDelta(mine, theirs, score)

		if data then
			data.Pvp.Rating = mine + delta
			if score == 1 then
				data.Pvp.Wins += 1
			elseif score == 0 then
				data.Pvp.Losses += 1
			else
				data.Pvp.Draws += 1
			end
			local xp = if score == 1 then pvp.WinXP elseif score == 0 then pvp.LossXP else pvp.DrawXP
			services.Skills:AddXP(player, Config.Combat.Skill, xp)
			services.Stats:Modify(player, pvp.StatDelta)
			services.Replication:MarkDirty(player)

			local format = if score == 1
				then Config.Text.PvpWin
				elseif score == 0 then Config.Text.PvpLoss
				else Config.Text.PvpDraw
			services.Replication:Notify(
				player,
				string.format(
					format,
					opponent.DisplayName,
					reasonText,
					math.floor(data.Pvp.Rating + 0.5),
					delta
				),
				if score == 1 then "success" elseif score == 0 then "warning" else "info"
			)
		end
		PvpService:_send(player)
	end

	-- Đưa cả hai về cạnh quầy sau một chút (người còn trong game và còn nhân vật)
	local back = PvpService:GetReturnPosition()
	if back then
		local returnTo: Vector3 = back
		task.delay(pvp.ReturnDelaySeconds, function()
			for _, player in { match.A, match.B } do
				if player.Parent == Players and matchOf[player] == nil and isAlive(player) then
					teleport(player, returnTo)
				end
			end
		end)
	end
end

function PvpService:Attack(player: Player)
	local match = matchOf[player]
	if not match or match.Phase ~= "fight" then
		return
	end
	local pvp = Config.Pvp
	local clock = os.clock()
	local last = match.LastAttack[player]
	if last and clock - last < pvp.AttackInterval * Config.Prompts.CooldownFactor then
		return
	end
	local opponent = opponentOf(match, player)
	local target = rootOf(opponent)
	if
		not target
		or not Validate.isWithin(
			player,
			target.Position,
			pvp.AttackRange + pvp.AttackRangeTolerance
		)
	then
		return
	end
	match.LastAttack[player] = clock

	local damage = self:GetDamage(services.Skills:GetLevel(player, Config.Combat.Skill))
	match.HP[opponent] = math.max(0, match.HP[opponent] - damage)
	if match.HP[opponent] <= 0 then
		finishMatch(match, player, "ko")
	else
		self:_send(player)
		self:_send(opponent)
	end
end

function PvpService:_tick(time: number)
	for i = #matches, 1, -1 do
		local match = matches[i]
		if match.Phase == "ended" then
			table.remove(matches, i)
			continue
		end
		-- Mất người chơi / nhân vật (cả lúc đếm ngược): người còn lại thắng
		local gone: Player? = nil
		for _, player in { match.A, match.B } do
			if player.Parent ~= Players or not isAlive(player) then
				gone = player
				break
			end
		end
		if gone then
			finishMatch(match, opponentOf(match, gone), "left")
			continue
		end

		if match.Phase == "countdown" then
			if time >= match.StartsAt then
				match.Phase = "fight"
				for _, player in { match.A, match.B } do
					services.Replication:Notify(player, Config.Text.PvpFight, "info")
					self:_send(player)
				end
			end
			continue
		end

		-- Ra khỏi vùng đấu: xử thua (nếu cả hai cùng ra thì người ra trước theo thứ tự A, B)
		local outside: Player? = nil
		for _, player in { match.A, match.B } do
			if not Validate.isWithin(player, match.Center, Config.Pvp.ZoneRadius) then
				outside = player
				break
			end
		end
		if outside then
			finishMatch(match, opponentOf(match, outside), "zone")
		elseif time >= match.EndsAt then
			local hpA, hpB = match.HP[match.A], match.HP[match.B]
			if hpA == hpB then
				finishMatch(match, nil, "timeout") -- hòa
			else
				finishMatch(match, if hpA > hpB then match.A else match.B, "timeout")
			end
		end
	end
end

return PvpService
