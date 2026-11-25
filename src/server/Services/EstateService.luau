--!strict
--[[
	EstateService — Khu dân cư (v0.8): mỗi người chơi đang online được gán một lô đất, trên đó hiện
	ngôi nhà và chiếc xe ĐẮT NHẤT họ đang thuê từ AURA, kèm biển tên. Người khác đi ngang là thấy.

	  * Lô đất là part mang tag Plot (attribute PlotIndex); map dựng sẵn có Config.World.Plot.Count lô.
	  * Gán lô khi dữ liệu tải xong (lô trống có số nhỏ nhất); trả lô khi người chơi rời game.
	    Hết lô thì người đến sau không có lô (vẫn chơi bình thường, có thông báo).
	  * Chỉ để KHOE: lô không cho tiền, chỉ số hay lợi thế nào. Không có Remote nào; client không yêu
	    cầu được gì ở đây. Nội dung lô suy ra từ data.Assets nên không lưu thêm dữ liệu.
	  * Refresh được ReplicationService gọi mỗi lần dựng snapshot; chỉ dựng lại khi nhà / xe đổi.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local EstateModel = require(script.Parent.Parent.Util.EstateModel)

type PlayerData = Types.PlayerData

type Plot = {
	Index: number,
	Part: BasePart,
	Owner: Player?,
	Key: string, -- "houseId|vehicleId" đang hiện (để chỉ dựng lại khi đổi)
}

local services: Types.Services = {}
local plots: { [number]: Plot } = {}
local plotOf: { [Player]: Plot } = setmetatable({}, { __mode = "k" }) :: any

local EstateService = {}

function EstateService:Init(allServices: Types.Services)
	services = allServices
end

function EstateService:Start()
	CollectionService:GetInstanceAddedSignal(Config.Tags.Plot):Connect(function(inst: Instance)
		self:_registerPlot(inst)
	end)
	for _, inst in CollectionService:GetTagged(Config.Tags.Plot) do
		self:_registerPlot(inst)
	end

	services.Data:OnLoaded(function(player: Player)
		self:_assign(player)
	end)
	services.Data:OnReleasing(function(player: Player)
		self:_release(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self:_release(player)
	end)
end

-- ───────────────────────────── API công khai ─────────────────────────────

-- Tài sản đắt nhất thuộc loại `kind` mà người chơi đang thuê (nil nếu không có). Bằng giá thì lấy id
-- nhỏ hơn theo thứ tự chữ cái để kết quả ổn định.
function EstateService:GetBest(data: PlayerData, kind: string): string?
	local bestId: string? = nil
	local bestPrice = -1
	for assetId in data.Assets do
		local def = Config.Assets[assetId]
		if def and def.Kind == kind then
			if
				def.Price > bestPrice or (def.Price == bestPrice and bestId and assetId < bestId)
			then
				bestId = assetId
				bestPrice = def.Price
			end
		end
	end
	return bestId
end

-- Số lô của người chơi (nil nếu không có lô)
function EstateService:GetPlotIndex(player: Player): number?
	local plot = plotOf[player]
	return if plot then plot.Index else nil
end

-- Dựng lại lô của người chơi nếu nhà / xe hiển thị đã đổi
function EstateService:Refresh(player: Player)
	local plot = plotOf[player]
	local data = services.Data:Get(player)
	if not plot or not data then
		return
	end
	local houseId: string? = self:GetBest(data, "house")
	local vehicleId: string? = self:GetBest(data, "vehicle")
	local key = `{houseId or ""}|{vehicleId or ""}`
	if key == plot.Key then
		return
	end
	plot.Key = key

	local names: { string } = {}
	for _, assetId in { houseId, vehicleId } do
		local def = if assetId then Config.Assets[assetId] else nil
		if def then
			table.insert(names, def.Name)
		end
	end
	local text = if #names > 0
		then string.format(Config.Text.PlotOwned, player.DisplayName, table.concat(names, " · "))
		else string.format(Config.Text.PlotBare, player.DisplayName)
	EstateModel.Render(plot.Part, text, true, houseId, vehicleId, plot.Index)
end

-- ───────────────────────────── Nội bộ ─────────────────────────────

function EstateService:_registerPlot(inst: Instance)
	if not inst:IsA("BasePart") or not inst:IsDescendantOf(Workspace) then
		return
	end
	local index = inst:GetAttribute(Config.Attributes.Plot)
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 then
		warn(
			`[EstateService] {inst:GetFullName()} thiếu attribute {Config.Attributes.Plot} hợp lệ`
		)
		return
	end
	if plots[index] then
		return
	end
	plots[index] = { Index = index, Part = inst, Owner = nil, Key = "" }
	EstateModel.Render(inst, Config.Text.PlotEmpty, false, nil, nil, index)
end

function EstateService:_assign(player: Player)
	if plotOf[player] then
		return
	end
	-- Lô trống có số nhỏ nhất
	local chosen: Plot? = nil
	for _, plot in plots do
		if not plot.Owner and (not chosen or plot.Index < chosen.Index) then
			chosen = plot
		end
	end
	if not chosen then
		services.Replication:Notify(player, Config.Text.PlotNone, "info")
		return
	end
	chosen.Owner = player
	chosen.Key = "?" -- khác mọi khoá thật: lần Refresh đầu luôn dựng
	plotOf[player] = chosen
	services.Replication:Notify(
		player,
		string.format(Config.Text.PlotAssigned, chosen.Index),
		"info"
	)
	self:Refresh(player)
end

function EstateService:_release(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	plot.Owner = nil
	plot.Key = ""
	EstateModel.Render(plot.Part, Config.Text.PlotEmpty, false, nil, nil, plot.Index)
end

return EstateService
