--!strict
--[[
	Format.luau — định dạng số/tiền kiểu Việt Nam (dấu chấm ngăn cách hàng nghìn).
]]

local Format = {}

-- 1250 -> "1.250"
function Format.number(n: number): string
	local rounded = math.floor(math.abs(n) + 0.5)
	-- "%.0f" an toàn với số lớn (tránh dạng 1e+12 của tostring)
	local digits = string.format("%.0f", rounded)
	local grouped = string.gsub(string.reverse(digits), "(%d%d%d)", "%1.")
	grouped = string.reverse(grouped)
	if string.sub(grouped, 1, 1) == "." then
		grouped = string.sub(grouped, 2)
	end
	if n < 0 and rounded > 0 then
		return "-" .. grouped
	end
	return grouped
end

-- 1250 -> "$1.250"
function Format.money(n: number): string
	if n < 0 then
		return "-$" .. Format.number(-n)
	end
	return "$" .. Format.number(n)
end

-- 125 giây -> "2:05" (số giây âm được coi là 0)
function Format.duration(seconds: number): string
	local total = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", total // 60, total % 60)
end

return Format
