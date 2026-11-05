--!strict
--[[
	StatsService — 6 chỉ số (0–100): Độ no, Năng lượng, Sạch sẽ, Hạnh phúc, Căng thẳng, Sức khỏe.

	Tick mỗi Config.Stats.TickSeconds giây (mặc định 5), dùng thời gian thực đo được giữa hai tick:
	  1. Độ no / Năng lượng / Sạch sẽ tụt theo Config.Stats.DecayPerMinute.
	  2. Mỗi nhu cầu dưới NeedLowThreshold: Hạnh phúc giảm, Căng thẳng tăng (tính cho TỪNG nhu cầu thấp).
	     Không nhu cầu nào thấp: Hạnh phúc hồi nhẹ, Căng thẳng dịu bớt.
	  3. Sức khỏe: hiệu ứng CỘNG DỒN (đói/kiệt sức -3, căng thẳng quá cao -1, mọi nhu cầu ổn +1 mỗi phút).
	  4. Sức khỏe về 0 => "kiệt sức": mất % tiền, respawn, chỉ số về mức an toàn. Không có bệnh tật.

	Service khác muốn đổi chỉ số phải gọi Modify() để được clamp 0–100, đồng bộ client và kiểm tra kiệt sức.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(script.Parent.Parent.Util.Validate)

type PlayerData = Types.PlayerData

local services: Types.Services = {}
local lastTick = os.clock()
-- Khoá yếu: không rò rỉ khi người chơi thoát
local exhausting: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local StatsService = {}

local function clampStat(value: number): number
	return math.clamp(value, Config.Stats.Min, Config.Stats.Max)
end

function StatsService:Init(allServices: Types.Services)
	services = allServices
	lastTick = os.clock()
end

function StatsService:Start()
	task.spawn(function()
		while true do
			task.wait(Config.Stats.TickSeconds)
			self:_tick()
		end
	end)
end

-- ───────────────────────────── API công khai ─────────────────────────────

function StatsService:Get(player: Player, statId: string): number?
	local data = services.Data:Get(player)
	if not data then
		return nil
	end
	return data.Stats[statId]
end

-- Cộng/trừ nhiều chỉ số cùng lúc. deltas = { Hunger = 30, Stress = -5 }.
-- Trả về false nếu chưa có dữ liệu người chơi.
function StatsService:Modify(player: Player, deltas: { [string]: number }): boolean
	local data = services.Data:Get(player)
	if not data then
		return false
	end
	for statId, delta in deltas do
		if Config.Stats.Defs[statId] and Validate.isFiniteNumber(delta) then
			data.Stats[statId] = clampStat((data.Stats[statId] or 0) + delta)
		else
			warn(
				`[StatsService] Bỏ qua chỉ số không hợp lệ: {tostring(statId)} = {tostring(
					delta
				)}`
			)
		end
	end
	self:_afterChange(player, data)
	return true
end

-- ───────────────────────────── Nội bộ ─────────────────────────────

function StatsService:_afterChange(player: Player, data: PlayerData)
	services.Replication:MarkDirty(player)
	if data.Stats.Health <= 0 then
		self:_exhaust(player, data)
	end
end

function StatsService:_tick()
	local now = os.clock()
	-- Giới hạn dt để một lần treo server không làm chỉ số rơi tự do
	local dt = math.min(now - lastTick, Config.Stats.TickSeconds * 3)
	lastTick = now
	local minutes = dt / 60 * Config.Stats.TimeScale

	for _, player in Players:GetPlayers() do
		local data = services.Data:Get(player)
		if data and not exhausting[player] then
			self:_applyTime(data.Stats, minutes)
			self:_afterChange(player, data)
		end
	end
end

-- Áp dụng công thức chỉ số cho `minutes` phút (xem docs/GDD.md mục "Công thức chỉ số")
function StatsService:_applyTime(stats: { [string]: number }, minutes: number)
	local cfg = Config.Stats

	-- 1. Các nhu cầu tụt dần
	for needId, perMinute in cfg.DecayPerMinute do
		stats[needId] = clampStat(stats[needId] - perMinute * minutes)
	end

	-- 2. Đếm nhu cầu thấp rồi chỉnh Hạnh phúc / Căng thẳng
	local lowCount = 0
	for _, needId in cfg.Needs do
		if stats[needId] < cfg.NeedLowThreshold then
			lowCount += 1
		end
	end
	if lowCount > 0 then
		stats.Happiness =
			clampStat(stats.Happiness + cfg.LowNeedHappinessPerMinute * lowCount * minutes)
		stats.Stress = clampStat(stats.Stress + cfg.LowNeedStressPerMinute * lowCount * minutes)
	else
		stats.Happiness = clampStat(stats.Happiness + cfg.AllGoodHappinessPerMinute * minutes)
		stats.Stress = clampStat(stats.Stress + cfg.AllGoodStressPerMinute * minutes)
	end

	-- 3. Sức khỏe: cộng dồn các hiệu ứng
	local healthPerMinute = 0
	if stats.Hunger <= 0 or stats.Energy <= 0 then
		healthPerMinute += cfg.StarvingHealthPerMinute
	end
	if stats.Stress >= cfg.StressDangerThreshold then
		healthPerMinute += cfg.StressDangerHealthPerMinute
	end
	if lowCount == 0 then
		healthPerMinute += cfg.HealthRegenPerMinute
	end
	stats.Health = clampStat(stats.Health + healthPerMinute * minutes)
end

-- Kiệt sức: mất % tiền (qua EconomyService), chỉ số về mức an toàn, respawn
function StatsService:_exhaust(player: Player, data: PlayerData)
	if exhausting[player] then
		return
	end
	exhausting[player] = true

	local lost = services.Economy:TakePercent(
		player,
		Config.Economy.ExhaustionLossPercent,
		Config.Reasons.Exhaustion
	)
	for statId, value in Config.Stats.SafeReset do
		data.Stats[statId] = value
	end
	services.Replication:MarkDirty(player)

	local percent = math.floor(Config.Economy.ExhaustionLossPercent * 100 + 0.5)
	services.Replication:Notify(
		player,
		string.format(Config.Text.Exhausted, Format.money(lost), percent),
		"error"
	)

	-- Respawn ở luồng riêng: LoadCharacterAsync yield cho tới khi nhân vật mới được tạo xong
	task.defer(function()
		if player.Parent == Players then
			local ok, err = pcall(function()
				player:LoadCharacterAsync()
			end)
			if not ok then
				warn(
					`[StatsService] LoadCharacterAsync thất bại cho {player.Name}: {tostring(
						err
					)}`
				)
			end
		end
		exhausting[player] = nil
	end)
end

return StatsService
