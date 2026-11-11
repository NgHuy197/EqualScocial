--!strict
--[[
	AuraService — AURA, siêu máy tính cai quản nền kinh tế (v0.3). Một cơ chế TRUNG TÍNH trong game.

	Nhịp: một "chu kỳ AURA" = Config.Aura.CycleSeconds, tính từ giờ server nên mọi máy chủ cùng nhịp.
	Mỗi chu kỳ, với từng người chơi đang online (mỗi người chỉ xử lý MỘT lần mỗi chu kỳ nhờ
	data.Aura.LastCycle, nên chuyển server giữa chừng không bị tính hai lần):
	  1. Phí duy trì tài sản (AssetService.ProcessCycle).
	  2. Cứ TaxEveryCycles chu kỳ: thuế lũy tiến theo tài sản ròng (phần vượt ngưỡng từng bậc),
	     chỉ thu tối đa bằng số tiền đang có; tiền thuế bị hủy khỏi nền kinh tế.
	Cấp server: sự kiện ngẫu nhiên có trọng số (công khai, áp cho mọi người như nhau), mở đấu giá
	tài sản hiếm, và bộ điều chỉnh lạm phát (đổi hệ số chính sách nhân vào phí duy trì và thuế,
	mỗi lần tối đa ±MaxStep, có nhật ký công khai).

	Người chơi KHÔNG bị tính phí khi ngoại tuyến: lúc vào game, LastCycle được đưa về chu kỳ hiện tại.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Prompts = require(script.Parent.Parent.Util.Prompts)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validate = require(script.Parent.Parent.Util.Validate)

type PlayerData = Types.PlayerData

type ActiveEvent = {
	Id: string,
	Def: Config.AuraEventDef,
	EndsAt: number,
	JobId: string?, -- chỉ sự kiện job_bonus
	Detail: string,
}

local AuraUpdate = Remotes.Event("AuraUpdate")
local OpenAura = Remotes.Event("OpenAura")
local GetAuraState = Remotes.Function("GetAuraState")

local services: Types.Services = {}
local policy = 1.0 -- hệ số chính sách nhân vào phí duy trì và thuế
local currentCycle = 0
local activeEvent: ActiveEvent? = nil
local taxExempt = false
local dirty = false
local log: { Types.AuraLogEntry } = {}
local flowIn, flowOut = 0, 0 -- tiền vào/ra tích lũy trong chu kỳ đang chạy
local lastIn, lastOut = 0, 0 -- tiền vào/ra của chu kỳ trước (hiện trong báo cáo)
local avgMoney, onlinePlayers = 0, 0
local limiter =
	RateLimiter.new(Config.RateLimits.GetAuraState.Calls, Config.RateLimits.GetAuraState.Window)

local function weakPlayerMap(): any
	return setmetatable({}, { __mode = "k" })
end
local lastWork: { [Player]: { JobId: string, Time: number } } = weakPlayerMap()

local AuraService = {}

local function cycleOf(serverTime: number): number
	return math.floor(serverTime / Config.Aura.CycleSeconds)
end

local function notifyAll(text: string)
	for _, player in Players:GetPlayers() do
		services.Replication:Notify(player, text, "aura")
	end
end

-- ───────────────────────────── Vòng đời ─────────────────────────────

function AuraService:Init(allServices: Types.Services)
	services = allServices
	for eventId, def in Config.AuraEvents do
		if def.Kind == "price" and (def.Category == nil or def.Multiplier == nil) then
			warn(`[AuraService] Sự kiện '{eventId}' (price) thiếu Category hoặc Multiplier`)
		elseif def.Kind == "job_bonus" and def.Multiplier == nil then
			warn(`[AuraService] Sự kiện '{eventId}' (job_bonus) thiếu Multiplier`)
		end
	end
end

function AuraService:Start()
	currentCycle = cycleOf(Workspace:GetServerTimeNow())

	-- Báo cáo AURA: phân loại mọi giao dịch thành tiền vào / tiền bị hút
	services.Economy:OnTransaction(function(transaction)
		local kind = Config.Aura.FlowReasons[transaction.Reason]
		if kind == "in" then
			flowIn += math.max(0, transaction.Delta)
		elseif kind == "out" then
			flowOut += math.max(0, -transaction.Delta)
		elseif kind == "refund" then
			flowOut = math.max(0, flowOut - math.max(0, transaction.Delta))
		end
	end)

	-- Vào game: không tính phí cho thời gian ngoại tuyến; gửi trạng thái AURA hiện tại
	services.Data:OnLoaded(function(player: Player, data: PlayerData)
		if data.Aura.LastCycle < currentCycle then
			data.Aura.LastCycle = currentCycle
		end
		AuraUpdate:FireClient(player, self:GetState())
	end)

	Prompts.BindTag(Config.Tags.Aura, function(_inst: Instance): Prompts.Spec?
		return {
			ActionText = Config.Text.AuraPrompt,
			ObjectText = Config.Text.AuraLabel,
			HoldDuration = 0,
			Cooldown = Config.Aura.OpenCooldown,
			OnTriggered = function(player: Player)
				OpenAura:FireClient(player)
			end,
		}
	end)

	GetAuraState.OnServerInvoke = function(player: Player)
		if not limiter:Allow(player) then
			return nil
		end
		local ok, view = pcall(function()
			return self:GetView(player)
		end)
		if not ok then
			warn(`[AuraService] Lỗi dựng trạng thái AURA: {tostring(view)}`)
			return nil
		end
		return view
	end

	-- Đồng hồ chu kỳ (bọc pcall để một lỗi lặt vặt không làm dừng cả vòng)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function()
				self:_tick(Workspace:GetServerTimeNow())
			end)
			if not ok then
				warn(`[AuraService] Lỗi đồng hồ AURA: {tostring(err)}`)
			end
		end
	end)

	-- Gửi trạng thái chung cho mọi client khi có thay đổi (gom lại, không gửi dồn dập)
	task.spawn(function()
		while true do
			task.wait(Config.Aura.BroadcastInterval)
			if dirty then
				dirty = false
				AuraUpdate:FireAllClients(self:GetState())
			end
		end
	end)
end

-- ───────────────────────────── API công khai ─────────────────────────────

function AuraService:MarkDirty()
	dirty = true
end

-- Người chơi có đứng trong PanelCloseDistance của một Trụ sở AURA không (kiểm tra phía server cho
-- mọi yêu cầu thuê / trả / đặt giá; cùng ngưỡng mà cửa sổ phía client tự đóng)
function AuraService:IsNearHq(player: Player): boolean
	for _, inst in CollectionService:GetTagged(Config.Tags.Aura) do
		if inst:IsDescendantOf(Workspace) then
			local anchor = Prompts.GetAnchor(inst)
			if
				anchor
				and Validate.isWithin(player, anchor.Position, Config.Aura.PanelCloseDistance)
			then
				return true
			end
		end
	end
	return false
end

function AuraService:GetCycle(): number
	return currentCycle
end

function AuraService:GetPolicyMultiplier(): number
	return policy
end

-- Hệ số giá đang áp dụng cho một nhóm hàng (1 nếu không có sự kiện giá cho nhóm đó)
function AuraService:GetPriceMultiplier(category: string): number
	local event = activeEvent
	if event and event.Def.Kind == "price" and event.Def.Category == category then
		return event.Def.Multiplier or 1
	end
	return 1
end

-- Hệ số lương đang áp dụng cho một nghề (sự kiện Thiếu lao động)
function AuraService:GetPayMultiplier(jobId: string): number
	local event = activeEvent
	if event and event.Def.Kind == "job_bonus" and event.JobId == jobId then
		return event.Def.Multiplier or 1
	end
	return 1
end

-- Ghi nhận người chơi vừa hoàn thành một lượt làm (để biết nghề nào đang thiếu người)
function AuraService:NoteWork(player: Player, jobId: string)
	lastWork[player] = { JobId = jobId, Time = os.clock() }
end

-- Số người đang làm từng nghề (đã hoàn thành một lượt trong ActiveWorkerSeconds giây gần nhất)
function AuraService:CountActiveWorkers(): { [string]: number }
	local counts: { [string]: number } = {}
	for jobId in Config.Jobs do
		counts[jobId] = 0
	end
	local now = os.clock()
	for player, work in lastWork do
		if player.Parent == Players and now - work.Time <= Config.Aura.ActiveWorkerSeconds then
			counts[work.JobId] = (counts[work.JobId] or 0) + 1
		end
	end
	return counts
end

-- Thuế lũy tiến theo tài sản ròng, đã nhân hệ số chính sách (số nguyên)
function AuraService:ComputeTax(netWorth: number): number
	local owed = 0
	local lower = 0
	for _, bracket in Config.Aura.TaxBrackets do
		if netWorth > lower then
			owed += (math.min(netWorth, bracket.Upto) - lower) * bracket.Rate
		end
		lower = bracket.Upto
	end
	return math.floor(owed * policy + 0.5)
end

-- Thời điểm (giờ server) của lần thu thuế kế tiếp
function AuraService:GetNextTaxAt(): number
	local every = Config.Aura.TaxEveryCycles
	local nextCycle = (math.floor(currentCycle / every) + 1) * every
	return nextCycle * Config.Aura.CycleSeconds
end

-- Trạng thái chung gửi cho mọi client
function AuraService:GetState(): Types.AuraState
	local event = activeEvent
	local eventState: Types.AuraEvent? = nil
	local priceMultipliers: { [string]: number } = {}
	local jobBonuses: { [string]: number } = {}
	if event then
		eventState = {
			Id = event.Id,
			Name = event.Def.Name,
			EndsAt = event.EndsAt,
			Detail = event.Detail,
		}
		if event.Def.Kind == "price" and event.Def.Category and event.Def.Multiplier then
			priceMultipliers[event.Def.Category] = event.Def.Multiplier
		elseif event.Def.Kind == "job_bonus" and event.JobId and event.Def.Multiplier then
			jobBonuses[event.JobId] = event.Def.Multiplier
		end
	end

	local logCopy: { Types.AuraLogEntry } = {}
	for index, entry in log do
		logCopy[index] = { Text = entry.Text, At = entry.At }
	end

	return {
		Cycle = currentCycle,
		CycleEndsAt = (currentCycle + 1) * Config.Aura.CycleSeconds,
		Event = eventState,
		PriceMultipliers = priceMultipliers,
		JobBonuses = jobBonuses,
		PolicyMultiplier = policy,
		NextTaxAt = self:GetNextTaxAt(),
		TaxExempt = taxExempt,
		AvgMoney = avgMoney,
		OnlinePlayers = onlinePlayers,
		Inflow = lastIn,
		Outflow = lastOut,
		Log = logCopy,
		Auction = services.Auction:GetState(),
	}
end

-- Trả lời GetAuraState: trạng thái chung + phần riêng của người hỏi. Có thể yield (đọc kho registry).
function AuraService:GetView(player: Player): Types.AuraView
	local stock: { [string]: number } = {}
	for assetId, def in Config.Assets do
		if def.Stock ~= nil then
			local remaining = services.Assets:GetRemaining(assetId)
			if remaining ~= nil then
				stock[assetId] = remaining
			end
		end
	end
	local netWorth = services.Leaderboard:GetNetWorth(player)
	return {
		State = self:GetState(),
		Stock = stock,
		IsLocalRegistry = services.Assets:IsLocalRegistry(),
		ExpectedTax = if taxExempt then 0 else self:ComputeTax(netWorth),
		Upkeep = services.Assets:GetUpkeep(player),
		NetWorth = netWorth,
	}
end

-- ───────────────────────────── Đồng hồ chu kỳ ─────────────────────────────

function AuraService:_tick(now: number)
	local event = activeEvent
	if event and now >= event.EndsAt then
		activeEvent = nil
		dirty = true
		notifyAll(string.format(Config.Text.EventEnded, event.Def.Name))
	end

	local cycle = cycleOf(now)
	-- Treo quá lâu (bỏ lỡ nhiều chu kỳ): chỉ xử lý chu kỳ gần nhất, không dồn phí một lúc
	if cycle - currentCycle > 3 then
		currentCycle = cycle - 1
	end
	while currentCycle < cycle do
		currentCycle += 1
		self:_onCycle(currentCycle, now)
	end
end

function AuraService:_onCycle(cycle: number, now: number)
	lastIn, lastOut = flowIn, flowOut
	flowIn, flowOut = 0, 0
	self:_updateStats()

	local isTaxCycle = cycle % Config.Aura.TaxEveryCycles == 0
	local exempt = isTaxCycle and taxExempt
	for _, player in Players:GetPlayers() do
		local data = services.Data:Get(player)
		-- Mỗi người chỉ xử lý một lần mỗi chu kỳ (kể cả khi chuyển server giữa chừng)
		if data and data.Aura.LastCycle < cycle then
			data.Aura.LastCycle = cycle
			services.Assets:ProcessCycle(player, data)
			if isTaxCycle then
				self:_collectTax(player, exempt)
			end
		end
	end
	if exempt then
		taxExempt = false -- kỳ thuế được miễn đã qua
	end

	if cycle % Config.Aura.EventEveryCycles == 0 then
		self:_tryStartEvent(now)
	end
	if cycle % Config.Aura.InflationEveryCycles == 0 then
		self:_adjustInflation(now)
	end
	if cycle % Config.Aura.AuctionEveryCycles == 0 then
		task.spawn(function()
			services.Auction:Open() -- có thể yield (đọc kho registry)
		end)
	end
	dirty = true
end

function AuraService:_collectTax(player: Player, exempt: boolean)
	if exempt then
		services.Replication:Notify(player, Config.Text.TaxHolidayApplied, "aura")
		return
	end
	local netWorth = services.Leaderboard:GetNetWorth(player)
	local tax = self:ComputeTax(netWorth)
	if tax <= 0 then
		return
	end
	-- Chỉ thu tối đa bằng số tiền đang có: không bao giờ làm âm tiền, không ghi nợ thuế
	local amount = math.min(tax, services.Economy:Get(player))
	if amount > 0 and services.Economy:TrySpend(player, amount, Config.Reasons.Tax) then
		services.Replication:Notify(
			player,
			string.format(Config.Text.TaxCollected, Format.money(amount), Format.money(netWorth)),
			"aura"
		)
	end
end

-- Tiền trung bình trên mỗi người chơi online (dùng cho báo cáo và bộ điều chỉnh lạm phát)
function AuraService:_updateStats()
	local total, count = 0, 0
	for _, player in Players:GetPlayers() do
		local data = services.Data:Get(player)
		if data then
			total += data.Money
			count += 1
		end
	end
	onlinePlayers = count
	avgMoney = if count > 0 then total / count else 0
end

-- ───────────────────────────── Sự kiện ngẫu nhiên ─────────────────────────────

-- Nghề có thể mở khóa bởi ít nhất một người chơi online (tránh chọn nghề không ai làm được)
local function isJobUnlockedBy(player: Player, job: Config.JobDef): boolean
	local requires: { Config.Requirement } = job.Requires or {}
	for _, requirement in requires do
		if services.Skills:GetLevel(player, requirement.Skill) < requirement.Level then
			return false
		end
	end
	return true
end

function AuraService:_pickShortageJob(): string?
	local players = Players:GetPlayers()
	if #players < Config.Aura.JobBonusMinPlayers then
		return nil
	end
	local workers = self:CountActiveWorkers()
	local best: { string } = {}
	local bestCount = math.huge
	local ids: { string } = {}
	for jobId in Config.Jobs do
		table.insert(ids, jobId)
	end
	table.sort(ids)
	for _, jobId in ids do
		local job = Config.Jobs[jobId]
		local available = false
		for _, player in players do
			if services.Data:Get(player) and isJobUnlockedBy(player, job) then
				available = true
				break
			end
		end
		if available then
			local count = workers[jobId] or 0
			if count < bestCount then
				bestCount = count
				best = { jobId }
			elseif count == bestCount then
				table.insert(best, jobId)
			end
		end
	end
	if #best == 0 then
		return nil
	end
	return best[math.random(1, #best)]
end

-- Bốc thăm một sự kiện theo trọng số; nếu sự kiện bốc được chưa đủ điều kiện thì bốc cái khác
function AuraService:_tryStartEvent(now: number)
	if activeEvent then
		return
	end
	local candidates: { { Id: string, Def: Config.AuraEventDef } } = {}
	for eventId, def in Config.AuraEvents do
		table.insert(candidates, { Id = eventId, Def = def })
	end
	table.sort(candidates, function(a, b)
		return a.Id < b.Id
	end)

	while #candidates > 0 do
		local total = 0
		for _, candidate in candidates do
			total += candidate.Def.Weight
		end
		local roll = math.random() * total
		local index = #candidates
		for i, candidate in candidates do
			roll -= candidate.Def.Weight
			if roll < 0 then
				index = i
				break
			end
		end
		local chosen = table.remove(candidates, index)
		if chosen and self:StartEvent(chosen.Id, now) then
			return
		end
	end
end

-- Bắt đầu một sự kiện cụ thể (công khai để test). Trả về false nếu chưa đủ điều kiện.
function AuraService:StartEvent(eventId: string, now: number): boolean
	local def = Config.AuraEvents[eventId]
	if not def or activeEvent then
		return false
	end

	local detail = def.Announce
	local jobId: string? = nil
	if def.Kind == "job_bonus" then
		jobId = self:_pickShortageJob()
		if not jobId then
			return false
		end
		detail = string.format(def.Announce, Config.Jobs[jobId].Name)
	elseif def.Kind == "tax_holiday" then
		if taxExempt then
			return false
		end
		taxExempt = true
	end

	activeEvent = {
		Id = eventId,
		Def = def,
		EndsAt = now + def.DurationSeconds,
		JobId = jobId,
		Detail = detail,
	}
	dirty = true
	notifyAll(string.format(Config.Text.EventStarted, def.Name, detail))
	return true
end

-- ───────────────────────────── Bộ điều chỉnh lạm phát ─────────────────────────────

function AuraService:_addLog(text: string, now: number)
	table.insert(log, { Text = text, At = now })
	while #log > Config.Aura.Inflation.LogSize do
		table.remove(log, 1)
	end
end

-- So tiền trung bình với mục tiêu rồi đổi từ từ hệ số chính sách (phí duy trì + thuế)
function AuraService:_adjustInflation(now: number)
	self:_updateStats()
	if onlinePlayers == 0 then
		return
	end
	local cfg = Config.Aura.Inflation
	local ratio = avgMoney / cfg.TargetAvgMoney
	if math.abs(ratio - 1) < cfg.DeadBand then
		return
	end
	local step = math.clamp((ratio - 1) * cfg.Gain, -cfg.MaxStep, cfg.MaxStep)
	local updated = math.clamp(policy * (1 + step), cfg.MinMultiplier, cfg.MaxMultiplier)
	if updated == policy then
		return -- đã chạm giới hạn hệ số
	end
	policy = updated

	local percent = math.floor(math.abs(step) * 100 + 0.5)
	local format = if step > 0 then Config.Text.InflationRaise else Config.Text.InflationLower
	local text =
		string.format(format, percent, Format.money(avgMoney), Format.money(cfg.TargetAvgMoney))
	self:_addLog(text, now)
	notifyAll(text)
	dirty = true
end

return AuraService
