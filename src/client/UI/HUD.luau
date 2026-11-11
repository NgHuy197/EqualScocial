--!strict
--[[
	HUD.luau — góc trên trái: tiền, nổi tiếng, 6 thanh chỉ số (xanh/vàng/đỏ) và level kỹ năng.
	Chỉ HIỂN THỊ dữ liệu server gửi xuống (Types.Snapshot); không tự tính toán gì cả.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Theme)

local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STAT_NAME_WIDTH = 92
local STAT_VALUE_WIDTH = 32

type StatRow = {
	Fill: Frame,
	Value: TextLabel,
}

type SkillRow = {
	Title: TextLabel,
	Info: TextLabel,
	Fill: Frame,
}

type Fields = {
	Money: TextLabel,
	Fame: TextLabel,
	NetWorth: TextLabel,
	Day: TextLabel,
	Aura: TextLabel,
	Season: TextLabel,
	Pvp: TextLabel,
	ProfileButton: TextButton,
	Stats: { [string]: StatRow },
	Skills: { [string]: SkillRow },
}

local HUD = {}
HUD.__index = HUD

export type HUD = typeof(setmetatable({} :: Fields, HUD))

local function newBar(parent: Instance): (Frame, Frame)
	local background = Instance.new("Frame")
	background.BackgroundColor3 = Theme.Colors.BarBackground
	background.BorderSizePixel = 0
	background.Parent = parent
	Theme.corner(background, 5)

	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = background
	Theme.corner(fill, 5)
	return background, fill
end

local function newHeader(parent: Instance, text: string, order: number)
	local header = Theme.label(parent, text, 14, Theme.Colors.TextMuted, Theme.Fonts.Bold)
	header.Size = UDim2.new(1, 0, 0, 18)
	header.LayoutOrder = order
end

function HUD.new(parent: Instance): HUD
	local root = Instance.new("Frame")
	root.Name = "HUD"
	-- IgnoreGuiInset của ScreenGui để false nên khung này nằm dưới thanh menu Roblox
	root.Position = UDim2.fromOffset(12, 12)
	root.Size = UDim2.fromOffset(264, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundColor3 = Theme.Colors.Panel
	root.BackgroundTransparency = 0.12
	root.Parent = parent
	Theme.corner(root, 10)
	Theme.padding(root, 10)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = root

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local money = Theme.label(root, "", 30, Theme.Colors.Money, Theme.Fonts.Bold)
	money.Name = "Money"
	money.Size = UDim2.new(1, 0, 0, 32)
	money.LayoutOrder = nextOrder()

	local fame = Theme.label(root, "", 18, Theme.Colors.Fame, Theme.Fonts.Semibold)
	fame.Name = "Fame"
	fame.Size = UDim2.new(1, 0, 0, 20)
	fame.LayoutOrder = nextOrder()

	local netWorth = Theme.label(root, "", 17, Theme.Colors.Text, Theme.Fonts.Semibold)
	netWorth.Name = "NetWorth"
	netWorth.Size = UDim2.new(1, 0, 0, 20)
	netWorth.LayoutOrder = nextOrder()

	local day = Theme.label(root, "", 16, Theme.Colors.TextMuted, Theme.Fonts.Regular)
	day.Name = "Day"
	day.Size = UDim2.new(1, 0, 0, 20)
	day.LayoutOrder = nextOrder()

	local aura =
		Theme.label(root, Config.Text.HudAuraNone, 16, Theme.KindColors.aura, Theme.Fonts.Regular)
	aura.Name = "Aura"
	aura.Size = UDim2.new(1, 0, 0, 20)
	aura.LayoutOrder = nextOrder()

	-- Mùa (v0.4): tên mùa, đếm ngược, điểm PvP và danh hiệu mới nhất (có thể xuống dòng)
	local season = Theme.label(root, "", 16, Theme.Colors.Fame, Theme.Fonts.Regular)
	season.Name = "Season"
	season.Size = UDim2.new(1, 0, 0, 20)
	season.AutomaticSize = Enum.AutomaticSize.Y
	season.TextWrapped = true
	season.LayoutOrder = nextOrder()

	-- Nút mở cửa sổ Hồ sơ (init.client nối sự kiện; HUD chỉ dựng nút)
	local profileButton = Instance.new("TextButton")
	profileButton.Name = "ProfileButton"
	profileButton.Size = UDim2.new(1, 0, 0, 26)
	profileButton.BackgroundColor3 = Theme.Colors.PanelLight
	profileButton.Font = Theme.Fonts.Semibold
	profileButton.Text = Config.Text.ProfileButton
	profileButton.TextSize = 16
	profileButton.TextColor3 = Theme.Colors.Text
	profileButton.LayoutOrder = nextOrder()
	profileButton.Parent = root
	Theme.corner(profileButton, 6)

	-- Trạng thái đấu trường: chỉ hiện khi đang chờ / đang đấu
	local pvp = Theme.label(root, "", 16, Theme.Colors.Accent, Theme.Fonts.Semibold)
	pvp.Name = "Pvp"
	pvp.Size = UDim2.new(1, 0, 0, 20)
	pvp.AutomaticSize = Enum.AutomaticSize.Y
	pvp.TextWrapped = true
	pvp.Visible = false
	pvp.LayoutOrder = nextOrder()

	newHeader(root, Config.Text.HudStats, nextOrder())

	local statRows: { [string]: StatRow } = {}
	for _, statId in Config.Stats.Order do
		local def = Config.Stats.Defs[statId]

		local row = Instance.new("Frame")
		row.Name = statId
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 20)
		row.LayoutOrder = nextOrder()
		row.Parent = root

		local name = Theme.label(row, def.Name, 17, Theme.Colors.Text, Theme.Fonts.Semibold)
		name.Size = UDim2.new(0, STAT_NAME_WIDTH, 1, 0)

		local background, fill = newBar(row)
		background.Position = UDim2.new(0, STAT_NAME_WIDTH + 4, 0.5, 0)
		background.AnchorPoint = Vector2.new(0, 0.5)
		background.Size = UDim2.new(1, -(STAT_NAME_WIDTH + STAT_VALUE_WIDTH + 8), 0, 12)

		local value = Theme.label(row, "", 16, Theme.Colors.Text, Theme.Fonts.Bold)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.new(0, STAT_VALUE_WIDTH, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right

		statRows[statId] = { Fill = fill, Value = value }
	end

	newHeader(root, Config.Text.HudSkills, nextOrder())

	local skillRows: { [string]: SkillRow } = {}
	for _, skillId in Config.Skills.Order do
		local def = Config.Skills.Defs[skillId]

		local row = Instance.new("Frame")
		row.Name = skillId
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 34)
		row.LayoutOrder = nextOrder()
		row.Parent = root

		local title = Theme.label(row, def.Name, 17, Theme.Colors.Text, Theme.Fonts.Semibold)
		title.Size = UDim2.new(0.6, 0, 0, 20)

		local info = Theme.label(row, "", 14, Theme.Colors.TextMuted, Theme.Fonts.Regular)
		info.AnchorPoint = Vector2.new(1, 0)
		info.Position = UDim2.fromScale(1, 0)
		info.Size = UDim2.new(0.4, 0, 0, 20)
		info.TextXAlignment = Enum.TextXAlignment.Right

		local background, fill = newBar(row)
		background.Position = UDim2.fromOffset(0, 24)
		background.Size = UDim2.new(1, 0, 0, 7)
		fill.BackgroundColor3 = Theme.Colors.Accent

		skillRows[skillId] = { Title = title, Info = info, Fill = fill }
	end

	return setmetatable({
		Money = money,
		Fame = fame,
		NetWorth = netWorth,
		Day = day,
		Aura = aura,
		Season = season,
		Pvp = pvp,
		ProfileButton = profileButton,
		Stats = statRows,
		Skills = skillRows,
	}, HUD)
end

-- Dòng "Hôm nay: Thứ Ba" (client tự tính từ giờ server, chỉ để hiển thị)
function HUD.SetDay(self: HUD, text: string)
	self.Day.Text = text
end

-- Dòng sự kiện đang chạy của AURA ("AURA: Khủng hoảng lương thực · 7:42")
function HUD.SetAura(self: HUD, text: string)
	self.Aura.Text = text
end

-- Dòng mùa ("Mùa 1 · còn 55 ngày · PvP 1000 điểm")
function HUD.SetSeason(self: HUD, text: string)
	self.Season.Text = text
end

-- Dòng đấu trường; nil = ẩn (không ở hàng chờ, không đang đấu)
function HUD.SetPvp(self: HUD, text: string?)
	self.Pvp.Visible = text ~= nil
	self.Pvp.Text = text or ""
end

function HUD.Render(self: HUD, state: Types.Snapshot)
	self.Money.Text = Format.money(state.Money)
	self.Fame.Text = string.format(Config.Text.HudFame, Format.number(state.Fame))

	local rank = state.Rank
	local rankText = if rank
		then string.format(Config.Text.HudRank, rank)
		else string.format(Config.Text.HudRankNone, Config.Leaderboard.TopCount)
	self.NetWorth.Text =
		`{string.format(Config.Text.HudNetWorth, Format.money(state.NetWorth))} · {rankText}`

	for statId, row in self.Stats do
		local def = Config.Stats.Defs[statId]
		local value = state.Stats[statId] or 0
		local fraction = math.clamp(value / Config.Stats.Max, 0, 1)
		row.Value.Text = tostring(math.floor(value + 0.5))
		TweenService:Create(row.Fill, BAR_TWEEN, {
			Size = UDim2.fromScale(fraction, 1),
			BackgroundColor3 = Theme.statColor(value, def.Inverted),
		}):Play()
	end

	for skillId, row in self.Skills do
		local def = Config.Skills.Defs[skillId]
		local skill = state.Skills[skillId]
		if skill then
			local maxed = skill.Level >= Config.Skills.MaxLevel
			local levelText = if maxed
				then string.format(Config.Text.SkillLevelMax, skill.Level)
				else string.format(Config.Text.SkillLevel, skill.Level)
			row.Title.Text = `{def.Name} · {levelText}`
			row.Info.Text = if maxed
				then ""
				else string.format(Config.Text.SkillXP, skill.XP, skill.Need)
			local fraction = if skill.Need > 0 then math.clamp(skill.XP / skill.Need, 0, 1) else 1
			TweenService:Create(row.Fill, BAR_TWEEN, { Size = UDim2.fromScale(fraction, 1) }):Play()
		end
	end
end

return HUD
