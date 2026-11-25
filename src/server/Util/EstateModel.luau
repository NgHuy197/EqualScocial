--!strict
--[[
	EstateModel.luau — dựng nhà và xe của một người chơi trên lô đất của họ ở Khu dân cư.

	Tách khỏi EstateService để logic gán lô không phụ thuộc cách dựng Instance (harness thay bằng bản giả).
	`plot` là part mang tag Plot: tâm lô trên mặt đất, LookVector chỉ ra đường. Mọi thứ dựng ra nằm trong
	một Folder "Estate" là con của `plot`, nên dựng lại chỉ cần xoá folder đó.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.Parent.World.Kit)
local Props = require(script.Parent.Parent.World.Props)

local FOLDER_NAME = "Estate"
local SIGN_NAME = "PlotSign"

local VEHICLE_COLORS = {
	Color3.fromRGB(226, 80, 70),
	Color3.fromRGB(70, 130, 210),
	Color3.fromRGB(250, 196, 60),
	Color3.fromRGB(90, 190, 140),
	Color3.fromRGB(170, 110, 220),
	Color3.fromRGB(240, 240, 244),
}

local EstateModel = {}

-- Chữ trên biển của lô (biển là part con tên PlotSign, do Landmarks dựng)
local function setSign(plot: BasePart, text: string, owned: boolean)
	local sign = plot:FindFirstChild(SIGN_NAME)
	if not sign or not sign:IsA("BasePart") then
		return
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local name = "Sign" .. face.Name
		local gui = sign:FindFirstChild(name)
		local found = if gui then gui:FindFirstChild("Text") else nil
		local textLabel: TextLabel
		if found and found:IsA("TextLabel") then
			textLabel = found
		else
			textLabel = Kit.sign(sign, face, "", { Padding = 8, LightInfluence = 0.3 })
			local parent = textLabel.Parent
			if parent then
				parent.Name = name
			end
		end
		textLabel.Text = text
		textLabel.TextColor3 = if owned
			then Config.Cosmetics.FameColor
			else Color3.fromRGB(200, 208, 224)
	end
end

-- Dựng lại lô: `signText` là chữ trên biển; `houseId` / `vehicleId` là id trong Config.Assets (nil = không
-- có). `colorIndex` chọn màu xe để các lô cạnh nhau khác màu.
function EstateModel.Render(
	plot: BasePart,
	signText: string,
	owned: boolean,
	houseId: string?,
	vehicleId: string?,
	colorIndex: number
)
	local old = plot:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	setSign(plot, signText, owned)
	if not houseId and not vehicleId then
		return
	end

	local folder = Kit.folder(plot, FOLDER_NAME)
	local base = CFrame.new(plot.Position.X, 0, plot.Position.Z) * plot.CFrame.Rotation
	local layout = Config.World.Plot
	if houseId then
		Props.house(folder, Kit.at(base, 0, 0, layout.HouseForward), houseId)
	end
	if vehicleId then
		local color = VEHICLE_COLORS[((colorIndex - 1) % #VEHICLE_COLORS) + 1]
		local pose = Kit.at(base, layout.VehicleRight, 0.2, layout.VehicleForward)
			* CFrame.Angles(0, math.rad(90), 0)
		Props.vehicle(folder, pose, vehicleId, color)
	end
end

return EstateModel
