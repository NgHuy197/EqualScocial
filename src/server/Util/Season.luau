--!strict
--[[
	Season.luau — logic THUẦN cho việc sang mùa (không gọi dịch vụ Roblox, dễ test).

	DataService gọi Season.Rollover ngay sau khi tải và reconcile dữ liệu, TRƯỚC khi báo cho các service
	khác (OnLoaded). Nhờ vậy:
	  * Tiền khóa đấu giá của mùa cũ (Aura.Escrow) bị bỏ cùng phần dữ liệu mùa cũ, không được "hoàn" sang
	    mùa mới (tiền vốn đã reset).
	  * Tài sản thuê / tài sản hiếm mùa cũ biến mất; registry mùa mới dùng store mới (hậu tố Season.Id).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type PlayerData = Types.PlayerData
type SeasonRecord = Types.SeasonRecord

local Season = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value :: { [any]: any } do
		copy[key] = deepCopy(child)
	end
	return copy
end

-- Danh hiệu đạt được từ thành tích một mùa (theo thứ tự trong Config.Season.TitleRules)
function Season.TitlesFor(record: SeasonRecord): { string }
	local titles: { string } = {}
	local matches = record.Wins + record.Losses + record.Draws
	for _, rule in Config.Season.TitleRules do
		local ok = true
		if rule.MinRating and record.Rating < rule.MinRating then
			ok = false
		end
		if rule.MinMatches and matches < rule.MinMatches then
			ok = false
		end
		if rule.MinPeakNetWorth and record.PeakNetWorth < rule.MinPeakNetWorth then
			ok = false
		end
		if ok then
			table.insert(titles, `{rule.Name} · {record.Name}`)
		end
	end
	return titles
end

-- Tên mùa cũ: không còn trong Config nên dựng từ Id
local function seasonName(id: number): string
	if id == Config.Season.Id then
		return Config.Season.Name
	end
	return `Mùa {id}`
end

--[[
	Nếu dữ liệu thuộc mùa khác mùa hiện tại: lưu hồ sơ mùa cũ vào History, trao danh hiệu, rồi đặt lại
	mọi trường KHÔNG thuộc Config.Season.Persistent về giá trị template. Trả về hồ sơ vừa lưu, hoặc nil
	nếu không cần sang mùa. Sửa `data` tại chỗ.
]]
function Season.Rollover(data: PlayerData, template: PlayerData): SeasonRecord?
	local currentId = Config.Season.Id
	if data.SeasonId == currentId then
		return nil
	end

	local record: SeasonRecord = {
		SeasonId = data.SeasonId,
		Name = seasonName(data.SeasonId),
		Money = data.Money,
		PeakNetWorth = math.max(data.PeakNetWorth, data.Money),
		Rating = data.Pvp.Rating,
		Wins = data.Pvp.Wins,
		Losses = data.Pvp.Losses,
		Draws = data.Pvp.Draws,
		Titles = {},
	}
	record.Titles = Season.TitlesFor(record)

	table.insert(data.History, record)
	while #data.History > Config.Season.HistorySize do
		table.remove(data.History, 1)
	end
	for _, title in record.Titles do
		table.insert(data.Titles, title)
	end

	-- Quay về vạch xuất phát: mọi trường không nằm trong Persistent lấy lại từ template
	local persistent: { [string]: boolean } = {}
	for _, key in Config.Season.Persistent do
		persistent[key] = true
	end
	local target = data :: any
	for key, value in template :: any do
		if not persistent[key] then
			target[key] = deepCopy(value)
		end
	end
	data.SeasonId = currentId
	return record
end

return Season
