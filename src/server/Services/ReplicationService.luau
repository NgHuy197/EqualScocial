--!strict
--[[
	ReplicationService — cầu nối server -> client.

	  * MarkDirty(player): đánh dấu có thay đổi. Vòng lặp gom lại và gửi snapshot tối đa
	    Config.Replication.SendRate lần/giây cho mỗi người chơi (không gửi gì nếu không có thay đổi).
	  * GetState (RemoteFunction): client lấy trạng thái lúc mới vào.
	  * Notify(player, text, kind): toast thông báo. kind: info | success | warning | error | levelup.

	Snapshot có `Seq` tăng dần theo từng người chơi; client bỏ qua snapshot cũ hơn bản đã áp dụng,
	nên GetState và StateUpdate đến lệch thứ tự cũng không sao.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local StateUpdate = Remotes.Event("StateUpdate")
local NotifyEvent = Remotes.Event("Notify")
local GetState = Remotes.Function("GetState")

local services: Types.Services = {}
local dirty: { [Player]: boolean } = {}
local sequence: { [Player]: number } = {}
local getStateLimiter =
	RateLimiter.new(Config.RateLimits.GetState.Calls, Config.RateLimits.GetState.Window)

local ReplicationService = {}

function ReplicationService:Init(allServices: Types.Services)
	services = allServices
end

function ReplicationService:Start()
	-- Có dữ liệu thì đẩy snapshot đầu tiên (client cũng tự gọi GetState khi khởi động)
	services.Data:OnLoaded(function(player: Player)
		dirty[player] = true
	end)

	GetState.OnServerInvoke = function(player: Player)
		if not getStateLimiter:Allow(player) then
			return nil
		end
		services.Data:WaitForData(player, Config.Replication.InitialStateTimeout)
		return self:BuildSnapshot(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		dirty[player] = nil
		sequence[player] = nil
		getStateLimiter:Clear(player)
	end)

	-- Vòng gom thay đổi
	task.spawn(function()
		while true do
			task.wait(1 / Config.Replication.SendRate)
			for player in dirty do
				dirty[player] = nil
				if player.Parent == Players then
					local snapshot = self:BuildSnapshot(player)
					if snapshot then
						StateUpdate:FireClient(player, snapshot)
					end
				end
			end
		end
	end)
end

-- ───────────────────────────── API công khai ─────────────────────────────

function ReplicationService:MarkDirty(player: Player)
	dirty[player] = true
end

function ReplicationService:Notify(player: Player, text: string, kind: string?)
	if type(text) ~= "string" or text == "" or player.Parent ~= Players then
		return
	end
	local resolved = kind or Config.Notify.DefaultKind
	if not table.find(Config.Notify.Kinds, resolved) then
		resolved = Config.Notify.DefaultKind
	end
	NotifyEvent:FireClient(player, text, resolved)
end

-- Dựng snapshot từ dữ liệu server (nil nếu chưa tải xong dữ liệu)
function ReplicationService:BuildSnapshot(player: Player): Types.Snapshot?
	local data = services.Data:Get(player)
	if not data then
		return nil
	end

	local seq = (sequence[player] or 0) + 1
	sequence[player] = seq

	local stats: { [string]: number } = {}
	for statId, value in data.Stats do
		stats[statId] = math.floor(value * 10 + 0.5) / 10
	end

	local skills: { [string]: Types.SkillSnapshot } = {}
	for _, skillId in Config.Skills.Order do
		local record = data.Skills[skillId]
		if record then
			local maxed = record.Level >= Config.Skills.MaxLevel
			skills[skillId] = {
				Level = record.Level,
				XP = math.floor(record.XP),
				Need = if maxed then 0 else services.Skills:XPNeeded(record.Level),
			}
		end
	end

	local owned: { [string]: boolean } = {}
	for itemId in data.Owned do
		owned[itemId] = true
	end

	return {
		Seq = seq,
		Money = data.Money,
		Fame = services.Shop:GetFame(player),
		NetWorth = services.Leaderboard:GetNetWorth(player),
		Rank = services.Leaderboard:GetRank(player),
		Stats = stats,
		Skills = skills,
		Owned = owned,
	}
end

return ReplicationService
