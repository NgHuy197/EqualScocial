--!strict
--[[
	Toast.luau — thông báo nổi ở giữa phía dưới màn hình.
	Mỗi toast tự mờ dần sau Config.UI.ToastSeconds; tối đa Config.UI.MaxToasts toast cùng lúc.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)

local FADE_SECONDS = 0.4

type Fields = {
	Container: Frame,
	Counter: number,
	Active: { Frame },
}

local Toast = {}
Toast.__index = Toast

export type Toast = typeof(setmetatable({} :: Fields, Toast))

function Toast.new(parent: Instance): Toast
	local container = Instance.new("Frame")
	container.Name = "Toasts"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -96)
	container.Size = UDim2.new(0.9, 0, 0, 280)
	container.BackgroundTransparency = 1
	container.ZIndex = 10 -- luôn vẽ trên HUD và cửa sổ cửa hàng
	container.Parent = parent

	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(480, 280)
	constraint.Parent = container

	-- Toast mới nằm dưới cùng, toast cũ đẩy lên trên
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	return setmetatable({ Container = container, Counter = 0, Active = {} }, Toast)
end

function Toast.Show(self: Toast, text: string, kind: string?)
	local color = Theme.KindColors[kind or Config.Notify.DefaultKind] or Theme.Colors.Accent

	self.Counter += 1
	local item = Instance.new("Frame")
	item.Name = "Toast"
	item.LayoutOrder = self.Counter
	item.Size = UDim2.fromScale(1, 0)
	item.AutomaticSize = Enum.AutomaticSize.Y
	item.BackgroundColor3 = Theme.Colors.Panel
	item.BackgroundTransparency = 0.1
	Theme.corner(item, 8)
	Theme.padding(item, 8)

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = item

	local label = Theme.label(item, text, 20, Theme.Colors.Text, Theme.Fonts.Semibold)
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center

	item.Parent = self.Container
	table.insert(self.Active, item)

	-- Quá số lượng cho phép: bỏ toast cũ nhất ngay
	while #self.Active > Config.UI.MaxToasts do
		local oldest = table.remove(self.Active, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	task.delay(Config.UI.ToastSeconds, function()
		if not item.Parent then
			return -- đã bị xoá
		end
		local info = TweenInfo.new(FADE_SECONDS)
		TweenService:Create(item, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		task.delay(FADE_SECONDS, function()
			local index = table.find(self.Active, item)
			if index then
				table.remove(self.Active, index)
			end
			item:Destroy()
		end)
	end)
end

return Toast
