--!strict
--[[
	ProfileWindow.luau — cửa sổ Hồ sơ (dựng bằng code): thành tích mùa này, danh hiệu, lịch sử các mùa.

	  * Mở bằng nút "Hồ sơ" trên HUD hoặc phím P; mở được ở bất cứ đâu (không gắn với vật thể trong map).
	  * Open(): lấy dữ liệu qua Fetch (RemoteFunction GetProfile) rồi vẽ. Chỉ dựng lại khi mở hoặc sau
	    một thao tác (Refetch), không dựng lại liên tục, nên nút luôn bấm được.
	  * Có nút gắn / gỡ danh hiệu và mua / dùng bảng tên màu. Nút chỉ GỬI yêu cầu (qua handlers);
	    server kiểm tra quyền sở hữu. Mua bằng Robux mở hộp thoại Game Pass của Roblox.
	Client chỉ HIỂN THỊ dữ liệu server trả về.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Theme = require(script.Parent.Theme)

type View = Types.ProfileView

export type Handlers = {
	Fetch: () -> View?,
	OnEquip: (id: string) -> (), -- "" = bỏ bảng tên màu
	OnEquipTitle: (title: string) -> (), -- "" = gỡ danh hiệu
	OnBuy: (gamePassId: number) -> (),
}

type Fields = {
	Root: Frame,
	Status: TextLabel,
	List: ScrollingFrame,
	Order: number,
	Token: number, -- tăng mỗi lần mở/đóng để bỏ kết quả của lần mở cũ
	Handlers: Handlers,
}

local ProfileWindow = {}
ProfileWindow.__index = ProfileWindow

export type ProfileWindow = typeof(setmetatable({} :: Fields, ProfileWindow))

function ProfileWindow.new(parent: Instance, handlers: Handlers): ProfileWindow
	local root = Instance.new("Frame")
	root.Name = "ProfileWindow"
	root.Visible = false
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(0.9, 0.85)
	root.BackgroundColor3 = Theme.Colors.Panel
	root.Parent = parent
	Theme.corner(root, 12)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(300, 300)
	constraint.MaxSize = Vector2.new(460, 560)
	constraint.Parent = root

	local title =
		Theme.label(root, Config.Text.ProfileTitle, 26, Theme.Colors.Text, Theme.Fonts.Bold)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -120, 0, 34)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(84, 34)
	closeButton.BackgroundColor3 = Theme.Colors.PanelLight
	closeButton.Font = Theme.Fonts.Bold
	closeButton.Text = Config.Text.ProfileClose
	closeButton.TextSize = 18
	closeButton.TextColor3 = Theme.Colors.Text
	closeButton.Parent = root
	Theme.corner(closeButton, 8)

	local status = Theme.label(root, "", 15, Theme.Colors.TextMuted)
	status.Position = UDim2.fromOffset(16, 46)
	status.Size = UDim2.new(1, -32, 0, 20)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Content"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(12, 70)
	list.Size = UDim2.new(1, -24, 1, -82)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local self = setmetatable({
		Root = root,
		Status = status,
		List = list,
		Order = 0,
		Token = 0,
		Handlers = handlers,
	}, ProfileWindow)

	closeButton.Activated:Connect(function()
		self:Close()
	end)
	return self
end

function ProfileWindow.IsOpen(self: ProfileWindow): boolean
	return self.Root.Visible
end

-- Một dòng chữ trong danh sách (tự xuống dòng)
function ProfileWindow._line(
	self: ProfileWindow,
	text: string,
	size: number,
	color: Color3,
	font: Enum.Font?,
	boxed: boolean?
): TextLabel
	self.Order += 1
	local label = Theme.label(self.List, text, size, color, font)
	label.Size = UDim2.new(1, -8, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.LayoutOrder = self.Order
	if boxed then
		label.BackgroundTransparency = 0
		label.BackgroundColor3 = Theme.Colors.PanelLight
		Theme.corner(label, 6)
		Theme.padding(label, 8)
	end
	return label
end

-- Một hàng: chữ bên trái, nút bên phải (nút tắt khi `onClick` = nil)
function ProfileWindow._buttonRow(
	self: ProfileWindow,
	name: string,
	text: string,
	textColor: Color3,
	buttonText: string,
	onClick: (() -> ())?
)
	self.Order += 1
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.new(1, -8, 0, 36)
	row.BackgroundColor3 = Theme.Colors.PanelLight
	row.LayoutOrder = self.Order
	row.Parent = self.List
	Theme.corner(row, 6)

	local label = Theme.label(row, text, 16, textColor, Theme.Fonts.Semibold)
	label.Position = UDim2.fromOffset(10, 0)
	label.Size = UDim2.new(1, -124, 1, 0)
	label.TextTruncate = Enum.TextTruncate.AtEnd

	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -6, 0.5, 0)
	button.Size = UDim2.fromOffset(104, 26)
	button.Font = Theme.Fonts.Bold
	button.TextSize = 15
	button.Text = buttonText
	button.TextColor3 = Theme.Colors.Text
	button.BackgroundColor3 = if onClick then Theme.Colors.Accent else Theme.Colors.Disabled
	button.AutoButtonColor = onClick ~= nil
	button.Parent = row
	Theme.corner(button, 6)
	if onClick then
		button.Activated:Connect(onClick)
	end
end

function ProfileWindow._clear(self: ProfileWindow)
	for _, child in self.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.Order = 0
end

function ProfileWindow._render(self: ProfileWindow, view: View)
	self:_clear()
	self.Status.Text = ""
	local pvp = view.Pvp
	self:_line(
		string.format(
			Config.Text.ProfileSeason,
			view.SeasonName,
			pvp.Rating,
			pvp.Wins,
			pvp.Losses,
			pvp.Draws
		),
		18,
		Theme.Colors.Text,
		Theme.Fonts.Semibold
	)
	self:_line(
		string.format(Config.Text.ProfilePeak, Format.money(view.PeakNetWorth)),
		16,
		Theme.Colors.Money
	)
	if view.XPBoost > 0 then
		local hours = math.floor(view.BoostSecondsLeft / 3600)
		local minutes = math.floor((view.BoostSecondsLeft % 3600) / 60)
		self:_line(
			string.format(
				Config.Text.ProfileCatchUp,
				math.floor(view.XPBoost * 100 + 0.5),
				string.format(Config.Text.DurationHoursMinutes, hours, minutes)
			),
			15,
			Theme.Colors.Accent
		)
	end
	local handlers = self.Handlers

	-- Bảng tên màu (Robux, chỉ trang trí)
	self:_line(Config.Text.ProfileNameTags, 14, Theme.Colors.TextMuted, Theme.Fonts.Bold)
	local anyEquipped = false
	for _, item in view.Cosmetics do
		local buttonText: string, onClick: (() -> ())?
		if item.Equipped then
			anyEquipped = true
			buttonText, onClick = Config.Text.CosmeticInUse, nil
		elseif item.Owned then
			buttonText = Config.Text.CosmeticUse
			onClick = function()
				handlers.OnEquip(item.Id)
			end
		elseif item.GamePassId > 0 then
			buttonText = Config.Text.CosmeticBuy
			onClick = function()
				handlers.OnBuy(item.GamePassId)
			end
		else
			buttonText, onClick = Config.Text.CosmeticSoon, nil
		end
		self:_buttonRow(item.Id, item.Name, Theme.Colors.Text, buttonText, onClick)
	end
	if anyEquipped then
		self:_buttonRow(
			"RemoveNameTag",
			Config.Text.CosmeticRemove,
			Theme.Colors.TextMuted,
			Config.Text.CosmeticRemoveButton,
			function()
				handlers.OnEquip("")
			end
		)
	end

	self:_line(Config.Text.ProfileTitles, 14, Theme.Colors.TextMuted, Theme.Fonts.Bold)
	if #view.Titles == 0 then
		self:_line(Config.Text.ProfileNoTitles, 15, Theme.Colors.TextMuted)
	else
		-- Mới nhất lên trước; mỗi danh hiệu có nút gắn lên bảng tên
		for i = #view.Titles, 1, -1 do
			local title = view.Titles[i]
			local equipped = title == view.EquippedTitle
			self:_buttonRow(
				`Title{i}`,
				title,
				Theme.Colors.Fame,
				if equipped then Config.Text.ProfileTitleEquipped else Config.Text.ProfileEquipTitle,
				if equipped
					then nil
					else function()
						handlers.OnEquipTitle(title)
					end
			)
		end
		if view.EquippedTitle ~= "" then
			self:_buttonRow(
				"RemoveTitle",
				Config.Text.ProfileRemoveTitle,
				Theme.Colors.TextMuted,
				Config.Text.ProfileRemoveTitleButton,
				function()
					handlers.OnEquipTitle("")
				end
			)
		end
	end

	self:_line(Config.Text.ProfileHistory, 14, Theme.Colors.TextMuted, Theme.Fonts.Bold)
	if #view.History == 0 then
		self:_line(Config.Text.ProfileNoHistory, 15, Theme.Colors.TextMuted)
	else
		for i = #view.History, 1, -1 do
			local record = view.History[i]
			local text = string.format(
				Config.Text.ProfileHistoryRow,
				record.Name,
				math.floor(record.Rating + 0.5),
				record.Wins,
				record.Losses,
				record.Draws,
				Format.money(record.PeakNetWorth)
			)
			if #record.Titles > 0 then
				text ..= "\n" .. string.format(
					Config.Text.ProfileHistoryTitles,
					table.concat(record.Titles, ", ")
				)
			end
			self:_line(text, 15, Theme.Colors.Text, nil, true)
		end
	end
end

function ProfileWindow.Open(self: ProfileWindow)
	self:_clear()
	self.Status.Text = Config.Text.ProfileLoading
	self.Root.Visible = true
	self.Token += 1
	local token = self.Token
	task.spawn(function()
		local view = self.Handlers.Fetch()
		if token ~= self.Token or not self.Root.Visible then
			return
		end
		if view then
			self:_render(view)
		else
			self.Status.Text = Config.Text.ProfileError
		end
	end)
end

-- Lấy lại dữ liệu sau một thao tác (chỉ khi cửa sổ đang mở)
function ProfileWindow.Refetch(self: ProfileWindow)
	if self:IsOpen() then
		self:Open()
	end
end

function ProfileWindow.Close(self: ProfileWindow)
	self.Token += 1
	self.Root.Visible = false
end

function ProfileWindow.Toggle(self: ProfileWindow)
	if self:IsOpen() then
		self:Close()
	else
		self:Open()
	end
end

return ProfileWindow
