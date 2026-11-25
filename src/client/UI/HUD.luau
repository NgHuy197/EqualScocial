--!strict
--[[
	HUD.luau — cột thẻ ở góc trên phải: ví (tiền, hạng, tài sản ròng, Nổi tiếng), thông tin (ngày,
	mùa, AURA, nút Hồ sơ, nhiệm vụ hướng dẫn), 6 chỉ số (xanh/vàng/đỏ) và 4 kỹ năng (thu gọn được).
	Dải trạng thái Đấu trường nằm giữa phía trên màn hình.

	Chỉ HIỂN THỊ dữ liệu server gửi xuống (Types.Snapshot); không tự tính toán gì cả.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Theme)

local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WIDTH = 252
local PADDING = 10

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
	Rank: TextLabel,
	Fame: TextLabel,
	NetWorth: TextLabel,
	Day: TextLabel,
	Aura: TextLabel,
	Season: TextLabel,
	Guide: TextLabel,
	GuideCard: Frame,
	Pvp: TextLabel,
	PvpBanner: Frame,
	ProfileButton: TextButton,
	SoundButton: TextButton,
	SkillsBody: Frame,
	SkillsToggle: TextButton,
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
	Theme.corner(background, 4)

	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = background
	Theme.corner(fill, 4)
	return background, fill
end

-- Một thẻ trong cột HUD: nền tối bo góc, các dòng con xếp dọc
local function newCard(parent: Instance, name: string, order: number, gap: number): Frame
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = order
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = parent
	Theme.panel(card, 12)
	Theme.padding(card, PADDING)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = card
	return card
end

-- Dòng chữ tự xuống dòng trong một thẻ
local function newLine(
	parent: Instance,
	name: string,
	order: number,
	textSize: number,
	color: Color3,
	font: Enum.Font
): TextLabel
	local label = Theme.label(parent, "", textSize, color, font)
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, textSize + 3)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	return label
end

function HUD.new(parent: Instance): HUD
	local root = Instance.new("Frame")
	root.Name = "HUD"
	-- Góc trên PHẢI: góc trên trái là cửa sổ chat của Roblox. IgnoreGuiInset của ScreenGui để false nên
	-- cột này nằm dưới thanh menu. Danh sách người chơi mặc định (cũng ở góc phải) được init.client tắt.
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -10, 0, 8)
	root.Size = UDim2.fromOffset(WIDTH, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.Parent = parent

	local column = Instance.new("UIListLayout")
	column.SortOrder = Enum.SortOrder.LayoutOrder
	column.Padding = UDim.new(0, 6)
	column.Parent = root

	-- ── Ví: tiền + hạng, tài sản ròng + Nổi tiếng ──
	local wallet = newCard(root, "Wallet", 1, 2)

	local top = Instance.new("Frame")
	top.Name = "Top"
	top.LayoutOrder = 1
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 30)
	top.Parent = wallet

	local money = Theme.label(top, "", 28, Theme.Colors.Money, Theme.Fonts.Bold)
	money.Name = "Money"
	money.Size = UDim2.new(1, -96, 1, 0)

	local rank = Theme.label(top, "", 14, Theme.Colors.Text, Theme.Fonts.Bold)
	rank.Name = "Rank"
	rank.AnchorPoint = Vector2.new(1, 0.5)
	rank.Position = UDim2.fromScale(1, 0.5)
	rank.Size = UDim2.fromOffset(92, 22)
	rank.BackgroundTransparency = 0.25
	rank.BackgroundColor3 = Theme.Colors.Accent
	rank.TextXAlignment = Enum.TextXAlignment.Center
	Theme.corner(rank, 11)

	local bottom = Instance.new("Frame")
	bottom.Name = "Bottom"
	bottom.LayoutOrder = 2
	bottom.BackgroundTransparency = 1
	bottom.Size = UDim2.new(1, 0, 0, 18)
	bottom.Parent = wallet

	local netWorth = Theme.label(bottom, "", 14, Theme.Colors.TextMuted, Theme.Fonts.Semibold)
	netWorth.Name = "NetWorth"
	netWorth.Size = UDim2.fromScale(0.62, 1)
	netWorth.TextTruncate = Enum.TextTruncate.AtEnd

	local fame = Theme.label(bottom, "", 14, Theme.Colors.Fame, Theme.Fonts.Semibold)
	fame.Name = "Fame"
	fame.AnchorPoint = Vector2.new(1, 0)
	fame.Position = UDim2.fromScale(1, 0)
	fame.Size = UDim2.fromScale(0.38, 1)
	fame.TextXAlignment = Enum.TextXAlignment.Right

	-- ── Thông tin: ngày, mùa, AURA, nút Hồ sơ ──
	local info = newCard(root, "Info", 2, 3)
	local day = newLine(info, "Day", 1, 15, Theme.Colors.Text, Theme.Fonts.Semibold)
	-- Mùa (v0.4): tên mùa, đếm ngược, điểm PvP và danh hiệu mới nhất (có thể xuống dòng)
	local season = newLine(info, "Season", 2, 14, Theme.Colors.Fame, Theme.Fonts.Regular)
	local aura = newLine(info, "Aura", 3, 14, Theme.Colors.Aura, Theme.Fonts.Regular)
	aura.Text = Config.Text.HudAuraNone

	-- Nút mở cửa sổ Hồ sơ (init.client nối sự kiện; HUD chỉ dựng nút)
	local profileButton = Instance.new("TextButton")
	profileButton.Name = "ProfileButton"
	profileButton.LayoutOrder = 4
	profileButton.Size = UDim2.new(1, 0, 0, 26)
	profileButton.BackgroundColor3 = Theme.Colors.PanelLight
	profileButton.Font = Theme.Fonts.Semibold
	profileButton.Text = Config.Text.ProfileButton
	profileButton.TextSize = 15
	profileButton.TextColor3 = Theme.Colors.Text
	profileButton.Parent = info
	Theme.corner(profileButton, 7)

	-- Nút bật / tắt âm thanh (init.client nối sự kiện)
	local soundButton = Instance.new("TextButton")
	soundButton.Name = "SoundButton"
	soundButton.LayoutOrder = 5
	soundButton.Size = UDim2.new(1, 0, 0, 22)
	soundButton.BackgroundColor3 = Theme.Colors.PanelLight
	soundButton.Font = Theme.Fonts.Regular
	soundButton.Text = Config.Text.HudMusicOn
	soundButton.TextSize = 14
	soundButton.TextColor3 = Theme.Colors.TextMuted
	soundButton.Parent = info
	Theme.corner(soundButton, 7)

	-- ── Nhiệm vụ hướng dẫn: chỉ hiện khi server gửi bước đang làm ──
	local guideCard = newCard(root, "Guide", 3, 2)
	guideCard.Visible = false
	local guideStroke = guideCard:FindFirstChildOfClass("UIStroke")
	if guideStroke then
		guideStroke.Color = Theme.Colors.Fame
		guideStroke.Transparency = 0.45
	end
	local guideHeader =
		Theme.label(guideCard, Config.Text.HudGuide, 12, Theme.Colors.Fame, Theme.Fonts.Bold)
	guideHeader.LayoutOrder = 1
	guideHeader.Size = UDim2.new(1, 0, 0, 14)
	local guide = newLine(guideCard, "Text", 2, 15, Theme.Colors.Text, Theme.Fonts.Semibold)

	-- ── Chỉ số: lưới 2 cột ──
	local needs = newCard(root, "Stats", 4, 4)
	local needsHeader =
		Theme.label(needs, Config.Text.HudStats, 12, Theme.Colors.TextMuted, Theme.Fonts.Bold)
	needsHeader.LayoutOrder = 1
	needsHeader.Size = UDim2.new(1, 0, 0, 14)

	local rows = math.ceil(#Config.Stats.Order / 2)
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.LayoutOrder = 2
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, rows * 30 + (rows - 1) * 5)
	grid.Parent = needs
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.CellSize = UDim2.new(0.5, -5, 0, 30)
	gridLayout.CellPadding = UDim2.fromOffset(10, 5)
	gridLayout.Parent = grid

	local statRows: { [string]: StatRow } = {}
	for index, statId in Config.Stats.Order do
		local def = Config.Stats.Defs[statId]

		local cell = Instance.new("Frame")
		cell.Name = statId
		cell.LayoutOrder = index
		cell.BackgroundTransparency = 1
		cell.Parent = grid

		local name = Theme.label(cell, def.Name, 14, Theme.Colors.Text, Theme.Fonts.Semibold)
		name.Size = UDim2.new(1, -30, 0, 16)

		local value = Theme.label(cell, "", 14, Theme.Colors.Text, Theme.Fonts.Bold)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.fromOffset(30, 16)
		value.TextXAlignment = Enum.TextXAlignment.Right

		local background, fill = newBar(cell)
		background.Position = UDim2.fromOffset(0, 20)
		background.Size = UDim2.new(1, 0, 0, 8)

		statRows[statId] = { Fill = fill, Value = value }
	end

	-- ── Kỹ năng: bấm tiêu đề để thu gọn / mở ra ──
	local skills = newCard(root, "Skills", 5, 4)
	local skillsToggle = Instance.new("TextButton")
	skillsToggle.Name = "Toggle"
	skillsToggle.LayoutOrder = 1
	skillsToggle.Size = UDim2.new(1, 0, 0, 16)
	skillsToggle.BackgroundTransparency = 1
	skillsToggle.AutoButtonColor = false
	skillsToggle.Font = Theme.Fonts.Bold
	skillsToggle.TextSize = 12
	skillsToggle.TextColor3 = Theme.Colors.TextMuted
	skillsToggle.TextXAlignment = Enum.TextXAlignment.Left
	skillsToggle.Parent = skills

	local skillsBody = Instance.new("Frame")
	skillsBody.Name = "Body"
	skillsBody.LayoutOrder = 2
	skillsBody.BackgroundTransparency = 1
	skillsBody.Size = UDim2.fromScale(1, 0)
	skillsBody.AutomaticSize = Enum.AutomaticSize.Y
	skillsBody.Parent = skills
	local skillsLayout = Instance.new("UIListLayout")
	skillsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	skillsLayout.Padding = UDim.new(0, 4)
	skillsLayout.Parent = skillsBody

	local skillRows: { [string]: SkillRow } = {}
	for index, skillId in Config.Skills.Order do
		local def = Config.Skills.Defs[skillId]

		local row = Instance.new("Frame")
		row.Name = skillId
		row.LayoutOrder = index
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 25)
		row.Parent = skillsBody

		local title = Theme.label(row, def.Name, 14, Theme.Colors.Text, Theme.Fonts.Semibold)
		title.Size = UDim2.new(0.66, 0, 0, 16)

		local skillInfo = Theme.label(row, "", 12, Theme.Colors.TextMuted, Theme.Fonts.Regular)
		skillInfo.AnchorPoint = Vector2.new(1, 0)
		skillInfo.Position = UDim2.fromScale(1, 0)
		skillInfo.Size = UDim2.new(0.34, 0, 0, 16)
		skillInfo.TextXAlignment = Enum.TextXAlignment.Right

		local background, fill = newBar(row)
		background.Position = UDim2.fromOffset(0, 19)
		background.Size = UDim2.new(1, 0, 0, 5)
		fill.BackgroundColor3 = Theme.Colors.Accent

		skillRows[skillId] = { Title = title, Info = skillInfo, Fill = fill }
	end

	-- ── Dải trạng thái Đấu trường: giữa phía trên, chỉ hiện khi đang chờ / đang đấu ──
	local pvpBanner = Instance.new("Frame")
	pvpBanner.Name = "PvpBanner"
	pvpBanner.AnchorPoint = Vector2.new(0.5, 0)
	pvpBanner.Position = UDim2.new(0.5, 0, 0, 8)
	pvpBanner.Size = UDim2.fromOffset(0, 34)
	pvpBanner.AutomaticSize = Enum.AutomaticSize.X
	pvpBanner.Visible = false
	pvpBanner.Parent = parent
	Theme.panel(pvpBanner, 17)
	local bannerStroke = pvpBanner:FindFirstChildOfClass("UIStroke")
	if bannerStroke then
		bannerStroke.Color = Theme.Colors.Accent
		bannerStroke.Transparency = 0.3
	end
	local bannerPadding = Instance.new("UIPadding")
	bannerPadding.PaddingLeft = UDim.new(0, 18)
	bannerPadding.PaddingRight = UDim.new(0, 18)
	bannerPadding.Parent = pvpBanner

	local pvp = Theme.label(pvpBanner, "", 18, Theme.Colors.Text, Theme.Fonts.Bold)
	pvp.Name = "Pvp"
	pvp.Size = UDim2.fromOffset(0, 34)
	pvp.AutomaticSize = Enum.AutomaticSize.X
	pvp.TextXAlignment = Enum.TextXAlignment.Center

	local self = setmetatable({
		Money = money,
		Rank = rank,
		Fame = fame,
		NetWorth = netWorth,
		Day = day,
		Aura = aura,
		Season = season,
		Guide = guide,
		GuideCard = guideCard,
		Pvp = pvp,
		PvpBanner = pvpBanner,
		ProfileButton = profileButton,
		SoundButton = soundButton,
		SkillsBody = skillsBody,
		SkillsToggle = skillsToggle,
		Stats = statRows,
		Skills = skillRows,
	}, HUD)

	skillsToggle.Activated:Connect(function()
		self:SetSkillsExpanded(not skillsBody.Visible)
	end)
	self:SetSkillsExpanded(true)
	return self
end

-- Mở / thu gọn danh sách kỹ năng (màn hình thấp thì init.client thu gọn sẵn)
function HUD.SetSkillsExpanded(self: HUD, expanded: boolean)
	self.SkillsBody.Visible = expanded
	self.SkillsToggle.Text = if expanded
		then Config.Text.HudSkillsCollapse
		else Config.Text.HudSkillsExpand
end

-- Chữ trên nút âm thanh theo trạng thái bật / tắt
function HUD.SetSound(self: HUD, enabled: boolean)
	self.SoundButton.Text = if enabled then Config.Text.HudMusicOn else Config.Text.HudMusicOff
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

-- Dải đấu trường; nil = ẩn (không ở hàng chờ, không đang đấu)
function HUD.SetPvp(self: HUD, text: string?)
	self.PvpBanner.Visible = text ~= nil
	self.Pvp.Text = text or ""
end

-- Thẻ nhiệm vụ hướng dẫn; nil = ẩn (đã xong hướng dẫn)
function HUD.SetGuide(self: HUD, text: string?)
	self.GuideCard.Visible = text ~= nil
	self.Guide.Text = text or ""
end

function HUD.Render(self: HUD, state: Types.Snapshot)
	self.Money.Text = Format.money(state.Money)
	self.Fame.Text = string.format(Config.Text.HudFame, Format.number(state.Fame))

	local rank = state.Rank
	self.Rank.Text = if rank
		then string.format(Config.Text.HudRank, rank)
		else string.format(Config.Text.HudRankNone, Config.Leaderboard.TopCount)
	self.NetWorth.Text = string.format(Config.Text.HudNetWorth, Format.money(state.NetWorth))

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
