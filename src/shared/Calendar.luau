--!strict
--[[
	Calendar.luau — lịch trong game, thuần tính toán (không lưu trạng thái).

	Ngày game suy ra từ giờ server nên mọi máy chủ và mọi người chơi luôn cùng một ngày:
	  ngày thứ N = floor(giờServer / Config.Calendar.DayLengthSeconds)
	  thứ trong tuần = N mod 7 + 1   (1 = Thứ Hai ... 7 = Chủ Nhật)

	Server và client đều gọi với `workspace:GetServerTimeNow()`. Client chỉ dùng để HIỂN THỊ ngày;
	việc lớp mở hay đóng cửa luôn do server quyết định.
]]

local Config = require(script.Parent.Config)

local Calendar = {}

-- Thứ trong tuần (1..7) tại thời điểm `serverTime` (giây)
function Calendar.GetWeekday(serverTime: number): number
	local dayNumber = math.floor(serverTime / Config.Calendar.DayLengthSeconds)
	return dayNumber % Config.Calendar.DaysPerWeek + 1
end

function Calendar.DayName(weekday: number): string
	return Config.Calendar.DayNames[weekday] or "?"
end

-- Lớp có mở cửa vào ngày hiện tại không? `openDays` là danh sách thứ (1..7)
function Calendar.IsOpen(openDays: { number }, serverTime: number): boolean
	return table.find(openDays, Calendar.GetWeekday(serverTime)) ~= nil
end

-- {1, 3, 5} -> "T2, T4, T6"
function Calendar.FormatDays(openDays: { number }): string
	local names: { string } = {}
	for _, weekday in openDays do
		table.insert(names, Config.Calendar.DayShortNames[weekday] or "?")
	end
	return table.concat(names, ", ")
end

return Calendar
