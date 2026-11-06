--!strict
--[[
	Bootstrap server của Equal Social.

	Thứ tự cố định:
	  1. Remotes.Init()                 tạo toàn bộ RemoteEvent/RemoteFunction
	  2. require tất cả service         theo SERVICE_ORDER
	  3. service:Init(services)         cho TẤT CẢ service (chỉ nhận bảng services, chưa chạy logic)
	  4. WorldBuilder.Build()           dựng map placeholder nếu chưa có World
	  5. service:Start()                cho TẤT CẢ service (kết nối sự kiện, chạy vòng lặp nền)

	Service KHÔNG require lẫn nhau; chúng gọi nhau qua bảng `services` nhận ở Init:
	  services.Economy:Add(player, 10, "job")

	Thêm service mới: tạo Services/XxxService.luau (có Init + Start) rồi thêm "Xxx" vào SERVICE_ORDER.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WorldBuilder = require(script.WorldBuilder)

-- Data phải đứng đầu (các service khác phụ thuộc dữ liệu); Replication đứng cuối vì đọc từ tất cả.
local SERVICE_ORDER = {
	"Data",
	"Economy",
	"Stats",
	"Skills",
	"Jobs",
	"Stations",
	"Shop",
	"School",
	"Combat",
	"Leaderboard",
	"Replication",
}

-- Phải chạy TRƯỚC khi require service, vì service lấy tham chiếu remote ngay ở mức module
Remotes.Init()

local Services = script.Services

-- require tĩnh để công cụ type-check hiểu được đường dẫn; khoá phải khớp với SERVICE_ORDER
local services: { [string]: any } = {
	Data = require(Services.DataService),
	Economy = require(Services.EconomyService),
	Stats = require(Services.StatsService),
	Skills = require(Services.SkillService),
	Jobs = require(Services.JobService),
	Stations = require(Services.StationService),
	Shop = require(Services.ShopService),
	School = require(Services.SchoolService),
	Combat = require(Services.CombatService),
	Leaderboard = require(Services.LeaderboardService),
	Replication = require(Services.ReplicationService),
}

for _, name in SERVICE_ORDER do
	assert(services[name], `Thiếu service '{name}' trong bảng services`)
end

for _, name in SERVICE_ORDER do
	services[name]:Init(services)
end

WorldBuilder.Build()

for _, name in SERVICE_ORDER do
	services[name]:Start()
end

print("[EqualSocial] Server đã sẵn sàng.")
