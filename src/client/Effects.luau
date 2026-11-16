--!strict
--[[
	Effects.luau — phản hồi tức thời phía client: số bay và âm thanh (CHỈ để nhìn / nghe).

	  * Số bay: "+$12" khi nhận tiền, "-$10" khi mất tiền (trên đầu nhân vật), "-10" tại chỗ quái khi đánh
	    trúng, "-5" đỏ trên đầu khi bị đánh. Server gửi qua RemoteEvent Effect; trạng thái thật vẫn đi
	    qua snapshot nên bỏ lỡ một hiệu ứng không làm sai dữ liệu.
	  * Âm thanh: file có sẵn trong client Roblox (Config.Sounds.Effects). Nhạc nền phát lần lượt các bài
	    trong Config.Sounds.Music.Tracks (để trống thì không có nhạc).
	  * SetEnabled(false) tắt toàn bộ âm thanh (nút trên HUD); lựa chọn chỉ giữ trong phiên chơi.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local Effects = {}

local enabled = true
local sounds: { [string]: Sound } = {}
local music: Sound? = nil
local trackIndex = 0
local active = 0

-- ───────────────────────────── Âm thanh ─────────────────────────────

local function getSound(name: string): Sound?
	local existing = sounds[name]
	if existing then
		return existing
	end
	local def = Config.Sounds.Effects[name]
	if not def then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "ES_" .. name
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	sound.Parent = SoundService
	sounds[name] = sound
	return sound
end

function Effects.Play(name: string)
	if not enabled then
		return
	end
	local sound = getSound(name)
	if sound then
		-- PlayLocalSound cho phép cùng một âm thanh chồng lên nhau (bấm nhanh, đánh liên tiếp)
		SoundService:PlayLocalSound(sound)
	end
end

local function nextTrack()
	local tracks = Config.Sounds.Music.Tracks
	local current = music
	if not current or #tracks == 0 then
		return
	end
	trackIndex = trackIndex % #tracks + 1
	current.SoundId = tracks[trackIndex]
	if enabled then
		current:Play()
	end
end

function Effects.IsEnabled(): boolean
	return enabled
end

function Effects.SetEnabled(value: boolean)
	enabled = value
	local current = music
	if current then
		if value then
			current:Resume()
		else
			current:Pause()
		end
	end
end

-- ───────────────────────────── Số bay ─────────────────────────────

local function ownHead(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, Config.Effects.HeadOffset, 0)
	end
	return nil
end

-- Chữ nổi tại `position`, bay lên rồi mờ dần
function Effects.Float(text: string, color: Color3, position: Vector3)
	local cfg = Config.Effects
	if active >= cfg.MaxActive then
		return
	end
	active += 1

	local anchor = Instance.new("Part")
	anchor.Name = "ES_Float"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	-- Lệch ngang một chút để nhiều số liên tiếp không chồng khít lên nhau
	anchor.Position = position
		+ Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10)
	anchor.Parent = Workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.SourceSansBold
	label.Text = text
	label.TextSize = 28
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(16, 18, 28)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui

	local info = TweenInfo.new(cfg.FloatSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, cfg.FloatRise, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, cfg.FloatSeconds + 0.1)
	task.delay(cfg.FloatSeconds, function()
		active -= 1
	end)
end

-- Xử lý một hiệu ứng server gửi xuống (dữ liệu được kiểm tra kiểu trước khi dùng)
function Effects.Handle(kind: any, value: any, position: any)
	if type(kind) ~= "string" or type(value) ~= "number" then
		return
	end
	local colors = Config.Effects.Colors
	local amount = math.floor(math.abs(value) + 0.5)
	if kind == "money" then
		local head = ownHead()
		if amount == 0 or not head then
			return
		end
		if value > 0 then
			Effects.Float("+" .. Format.money(amount), colors.gain, head)
			Effects.Play("coin")
		else
			Effects.Float("-" .. Format.money(amount), colors.loss, head)
			Effects.Play("spend")
		end
	elseif kind == "hit" then
		local at = if typeof(position) == "Vector3" then position else ownHead()
		if at then
			Effects.Float(string.format(Config.Text.EffectHit, amount), colors.hit, at)
		end
		Effects.Play("hit")
	elseif kind == "hurt" then
		local head = ownHead()
		if head then
			Effects.Float(string.format(Config.Text.EffectHit, amount), colors.hurt, head)
		end
		Effects.Play("hurt")
	end
end

function Effects.Start()
	if #Config.Sounds.Music.Tracks > 0 then
		local sound = Instance.new("Sound")
		sound.Name = "ES_Music"
		sound.Volume = Config.Sounds.Music.Volume
		sound.Parent = SoundService
		music = sound
		sound.Ended:Connect(nextTrack)
		nextTrack()
	end
end

return Effects
