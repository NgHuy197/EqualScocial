--!strict
--[[
	Validate.luau — kiểm tra dữ liệu không đáng tin (từ client) và vị trí người chơi.
	Mọi handler RemoteEvent/RemoteFunction/ProximityPrompt phải dùng các hàm này.
]]

local Players = game:GetService("Players")

local Validate = {}

local DEFAULT_ID_LENGTH = 32

-- Là một Player thật sự đang ở trong game?
function Validate.isPlayer(value: any): boolean
	if typeof(value) ~= "Instance" then
		return false
	end
	local instance = value :: Instance
	return instance:IsA("Player") and instance.Parent == Players
end

-- Id hợp lệ: chuỗi chữ/số/gạch dưới, 1..maxLength ký tự
function Validate.isId(value: any, maxLength: number?): boolean
	if type(value) ~= "string" then
		return false
	end
	local text = value :: string
	if #text == 0 or #text > (maxLength or DEFAULT_ID_LENGTH) then
		return false
	end
	return string.match(text, "^[%w_]+$") ~= nil
end

-- Số hữu hạn (không NaN, không ±inf)
function Validate.isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	local n = value :: number
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Vị trí HumanoidRootPart nếu nhân vật còn sống, ngược lại nil
function Validate.getRootPosition(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

-- Người chơi (còn sống) có đứng trong bán kính maxDistance quanh position không?
function Validate.isWithin(player: Player, position: Vector3, maxDistance: number): boolean
	local playerPosition = Validate.getRootPosition(player)
	if not playerPosition then
		return false
	end
	return (playerPosition - position).Magnitude <= maxDistance
end

return Validate
