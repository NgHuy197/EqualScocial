--!strict
--[[
	Prompts.luau — gắn ProximityPrompt theo tag CollectionService, kèm bảo vệ phía server.

	Vì sao cần: ProximityPrompt.Triggered do client báo lên, exploit có thể bỏ qua thời gian giữ
	phím hoặc gọi liên tục. Mỗi prompt ở đây đều:
	  1. kiểm tra người gọi là Player thật, nhân vật còn sống;
	  2. kiểm tra khoảng cách tới điểm neo (kèm dung sai nhỏ cho độ trễ mạng);
	  3. áp cooldown theo từng người chơi (mặc định ≈ HoldDuration * CooldownFactor),
	     nên tốc độ tối đa của kẻ gian cũng không vượt tốc độ của người chơi bình thường.

	Dùng:
	  Prompts.BindTag(tag, function(inst) return { ActionText = ..., OnTriggered = ... } end)
	Service chỉ cần mô tả hành vi; model thật sau này chỉ cần gắn tag + attribute là chạy.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Validate = require(script.Parent.Validate)

export type Spec = {
	ActionText: string,
	ObjectText: string,
	HoldDuration: number,
	MaxActivationDistance: number?,
	Cooldown: number?, -- giây; mặc định HoldDuration * Config.Prompts.CooldownFactor
	OnTriggered: (player: Player, inst: Instance) -> (),
	-- Gọi khi người chơi bắt đầu giữ phím (dùng để báo sớm "bạn không làm được"). Đã có throttle.
	OnHoldBegan: ((player: Player, inst: Instance) -> ())?,
}

type Binding = {
	Prompt: ProximityPrompt,
	Connections: { RBXScriptConnection },
}

local Prompts = {}

-- Điểm neo của một instance được gắn tag: chính nó nếu là BasePart, hoặc PrimaryPart / part đầu tiên
-- của Model. ProximityPrompt và mọi phép kiểm tra khoảng cách đều dùng điểm này.
function Prompts.GetAnchor(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") and inst.PrimaryPart then
		return inst.PrimaryPart
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function weakPlayerMap(): { [Player]: number }
	return setmetatable({}, { __mode = "k" }) :: any
end

-- Gắn prompt cho mọi instance mang tag (hiện có và sẽ thêm sau này).
-- `factory` trả về Spec, hoặc nil nếu instance cấu hình sai (đã tự warn).
function Prompts.BindTag(tag: string, factory: (inst: Instance) -> Spec?)
	local bindings: { [Instance]: Binding } = {}

	local function unbind(inst: Instance)
		local binding = bindings[inst]
		if not binding then
			return
		end
		bindings[inst] = nil
		for _, connection in binding.Connections do
			connection:Disconnect()
		end
		binding.Prompt:Destroy()
	end

	local function bind(inst: Instance)
		if bindings[inst] or not inst:IsDescendantOf(Workspace) then
			return
		end
		local anchor = Prompts.GetAnchor(inst)
		if not anchor then
			warn(
				`[Prompts] {inst:GetFullName()} có tag {tag} nhưng không có BasePart nào để gắn prompt`
			)
			return
		end
		local spec = factory(inst)
		if not spec then
			return
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ES_Prompt"
		prompt.ActionText = spec.ActionText
		prompt.ObjectText = spec.ObjectText
		prompt.HoldDuration = spec.HoldDuration
		prompt.MaxActivationDistance = spec.MaxActivationDistance
			or Config.Prompts.MaxActivationDistance
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = anchor

		local cooldown = math.max(
			spec.Cooldown or spec.HoldDuration * Config.Prompts.CooldownFactor,
			Config.Prompts.MinCooldown
		)
		local lastUse = weakPlayerMap()
		local lastHoldNotice = weakPlayerMap()

		-- Kiểm tra chung: người chơi hợp lệ, còn sống và đứng đủ gần điểm neo
		local function passesGuard(player: any): boolean
			if not Validate.isPlayer(player) then
				return false
			end
			local limit = prompt.MaxActivationDistance + Config.Prompts.DistanceTolerance
			return Validate.isWithin(player :: Player, anchor.Position, limit)
		end

		local connections: { RBXScriptConnection } = {}

		table.insert(
			connections,
			prompt.Triggered:Connect(function(player: Player)
				if not passesGuard(player) then
					return
				end
				local now = os.clock()
				local last = lastUse[player]
				if last and now - last < cooldown then
					return -- còn trong cooldown: bỏ qua im lặng
				end
				lastUse[player] = now
				spec.OnTriggered(player, inst)
			end)
		)

		local onHoldBegan = spec.OnHoldBegan
		if onHoldBegan then
			table.insert(
				connections,
				prompt.PromptButtonHoldBegan:Connect(function(player: Player)
					if not passesGuard(player) then
						return
					end
					local now = os.clock()
					local last = lastHoldNotice[player]
					if last and now - last < Config.Prompts.HoldNoticeThrottle then
						return
					end
					lastHoldNotice[player] = now
					onHoldBegan(player, inst)
				end)
			)
		end

		bindings[inst] = { Prompt = prompt, Connections = connections }
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unbind)
	for _, inst in CollectionService:GetTagged(tag) do
		task.spawn(bind, inst)
	end
end

return Prompts
