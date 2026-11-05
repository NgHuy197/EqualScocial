# Equal Social — hướng dẫn cho Claude Code

Game Roblox nhiều người chơi, viết bằng Luau + Rojo. **Mọi chữ hiển thị trong game phải là tiếng Việt.**

> **Trước khi làm bất kỳ tính năng mới nào: đọc [docs/GDD.md](docs/GDD.md)** (tầm nhìn, công thức, số liệu, thiết kế các giai đoạn sau, câu hỏi thiết kế còn mở). Nếu thay đổi thiết kế hoặc số liệu, cập nhật cả GDD.

## Tổng quan

Một xã hội giống ngoài đời, nhưng mọi người chơi **xuất phát như nhau**: cùng tiền ($100), cùng chỉ số, không gia thế, không bệnh tật. Người chơi cạnh tranh công bằng bằng cách học skill, làm nghề, luyện tập, đấu với nhau rồi mua tài sản để khoe. Mọi tài sản thuộc sở hữu và do siêu máy tính AI **AURA** cai quản. Lối chơi giống Stardew Valley + The Sims, nhưng đề cao tương tác và cạnh tranh giữa người chơi.

Trạng thái: **MVP v0.1** (xem GDD mục 4). Lộ trình: v0.2 trường học/đánh quái/leaderboard → v0.3 AURA → v0.4 PvP + Season.

## Lệnh

```bash
rokit install                                  # cài rojo, selene, stylua, luau-lsp theo rokit.toml
rojo serve                                     # đồng bộ vào Studio (plugin Rojo → Connect)
rojo build -o EqualSocial.rbxl                 # build file place để kiểm tra project (đã được .gitignore)
stylua src                                     # format (stylua --check src để chỉ kiểm tra)
selene generate-roblox-std                     # chỉ cần chạy 1 lần để sinh roblox.yml
selene src                                     # lint
rojo sourcemap default.project.json -o sourcemap.json   # cần cho luau-lsp
```

Type-check `--!strict` bằng luau-lsp (cần file định nghĩa API Roblox `globalTypes.d.luau`, tải từ trang luau-lsp):

```bash
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src
```

Sau mỗi thay đổi code, tối thiểu phải qua: `stylua --check src`, `selene src`, type-check luau-lsp (không lỗi).

## Cấu trúc

```
src/shared  → ReplicatedStorage.Shared                       Config, Remotes, Format, Types
src/server  → ServerScriptService.Server (init.server.luau)  Services/, Util/, WorldBuilder
src/client  → StarterPlayer.StarterPlayerScripts.Client      init.client.luau, UI/
```

- `Config.luau`: **toàn bộ** số liệu cân bằng và câu chữ hiển thị (`Config.Text`).
- `Remotes.luau`: danh sách RemoteEvent/RemoteFunction. Server gọi `Remotes.Init()` một lần; nơi khác dùng `Remotes.Event(name)` / `Remotes.Function(name)`.
- `Services/*`: `DataService`, `EconomyService`, `StatsService`, `SkillService`, `JobService`, `StationService`, `ShopService`, `ReplicationService`.
- `Util/*`: `Validate` (kiểm tra dữ liệu/khoảng cách), `RateLimiter`, `Prompts` (gắn ProximityPrompt theo tag có cooldown + kiểm tra khoảng cách phía server).
- `WorldBuilder`: dựng map placeholder nếu Workspace chưa có `World`; map thật chỉ cần gắn **tag + attribute** (xem bên dưới).

## Luật kiến trúc (BẮT BUỘC)

1. **Server-authoritative.** Mọi tiền, chỉ số, giao dịch, XP, sở hữu đều tính và lưu trên server. Client chỉ hiển thị và gửi yêu cầu. **Không bao giờ tin dữ liệu client gửi lên.**
2. **Chỉ `EconomyService` được đổi tiền**, qua `Add`, `TrySpend`, `TakePercent`. Mỗi hàm bắt buộc có `reason` (dùng `Config.Reasons`) để AURA sau này đánh thuế và ghi log. Không bao giờ ghi `data.Money` ở nơi khác.
3. **Mọi con số cân bằng nằm trong `Config.luau`** (giá, lương, tốc độ tụt chỉ số, khoảng cách, cooldown, rate-limit...). Thêm nghề / trạm / món hàng mới chỉ cần sửa Config; WorldBuilder tự xếp khối placeholder cho nghề, trạm, cửa hàng mới.
4. **Pattern service.** Mỗi service là một ModuleScript có `Init(services)` và `Start()`. `init.server.luau` require tất cả, gọi `Init` cho tất cả, dựng world, rồi mới gọi `Start` cho tất cả, theo thứ tự cố định trong `SERVICE_ORDER`. **Không require chéo giữa các service**: gọi nhau qua bảng `services` (ví dụ `services.Economy:Add(...)`). `Init` chỉ lưu tham chiếu/chuẩn bị dữ liệu; kết nối sự kiện và vòng lặp nền đặt trong `Start`.
5. **Bảo mật Remote.** Mọi handler RemoteEvent/RemoteFunction phải: kiểm tra kiểu và độ dài tham số (`Validate`), kiểm tra khoảng cách phía server, và rate-limit (`RateLimiter`, cấu hình ở `Config.RateLimits`). Handler RemoteFunction bọc `pcall` và trả thông báo lỗi tiếng Việt.
6. **ProximityPrompt cũng phải có cooldown phía server.** Luôn gắn qua `Prompts.BindTag`, không tự `Instance.new("ProximityPrompt")` rải rác. Cooldown mặc định ≈ `HoldDuration * Config.Prompts.CooldownFactor`.
7. **Không yield giữa "kiểm tra" và "ghi"** khi xử lý mua bán (tránh mua đúp bằng request song song).
8. **Dữ liệu người chơi** chỉ truy cập qua `services.Data:Get(player)`; khi thêm trường mới, thêm vào template trong `DataService` (reconcile tự bổ sung cho người chơi cũ). Thêm migration nếu đổi cấu trúc cũ và tăng `Config.Data.SchemaVersion`.
9. **Client không có logic game.** UI chỉ vẽ `Snapshot` do server gửi (`ReplicationService`). Nút bấm chỉ gửi yêu cầu.

## Ràng buộc chính sách Roblox (không được vi phạm)

- **Không** nội dung lãng mạn/hẹn hò (không hôn, nắm tay, cưới hỏi, "bạn trai/bạn gái"...) và **không** chính trị đời thực. AURA đánh thuế/quản lý tài sản chỉ là cơ chế trong game, giữ trung tính, không ám chỉ chính phủ hay đảng phái thật.
- **Robux chỉ dùng bán cosmetic** (skin, emote, hiệu ứng, khung tên...). **Không** bán tiền trong game, chỉ số, XP, skill, "nổi tiếng" hay bất kỳ lợi thế nào; không bán hộp ngẫu nhiên. Tiền trong game không được mua bằng Robux và không được quy đổi ra Robux.
- Mọi văn bản người dùng nhập (nếu có sau này) phải qua `TextService:FilterStringAsync`.
- Cá cược (v0.4) chỉ dùng tiền trong game; cần rà lại chính sách Roblox về nội dung giống cờ bạc trước khi làm (xem GDD).

## Quy ước code

- Luau, `--!strict` ở mọi file, annotation kiểu ở chỗ hợp lý; comment **tiếng Việt** cho logic quan trọng.
- Định dạng bằng StyLua (tab, cột 100). Lint bằng Selene (`std = "roblox"`).
- Font UI dùng họ `SourceSans*` (hiển thị tốt dấu tiếng Việt). Không dùng emoji trong UI.
- Tag CollectionService và attribute lấy từ `Config.Tags` / `Config.Attributes`, không gõ chuỗi trực tiếp.
- Tham số `reason` của EconomyService lấy từ `Config.Reasons`.

## Thay map placeholder bằng model thật

Model/Part đặt trong Workspace, có ít nhất một `BasePart` (prompt gắn vào `PrimaryPart` hoặc part đầu tiên), rồi:

| Loại | Tag (`Config.Tags`) | Attribute | Giá trị |
| --- | --- | --- | --- |
| Nghề | `ES_Job` | `JobId` | khoá trong `Config.Jobs` (`warehouse`, `barista`) |
| Trạm | `ES_Station` | `StationId` | khoá trong `Config.Stations` (`shower`, `bed`, `bench`) |
| Cửa hàng | `ES_Shop` | `ShopId` | khoá trong `Config.Shops` (`restaurant`, `fashion`) |

Nếu Workspace đã có thư mục/model tên `World`, WorldBuilder không dựng gì thêm.

## Checklist test thủ công (MVP)

Chạy trong Studio (Play, hoặc Test → 2 người chơi). Để test nhanh theo thời gian, đặt tạm `Config.Stats.TimeScale = 60` (nhớ trả về `1`).

1. **Khởi động**: Output có `[WorldBuilder] Đã dựng map placeholder` và `[EqualSocial] Server đã sẵn sàng`, không có lỗi đỏ. HUD hiện **$100**, Nổi tiếng 0, 6 thanh chỉ số (Độ no/Năng lượng/Sạch sẽ 100, Hạnh phúc 70, Căng thẳng 10, Sức khỏe 100), 2 kỹ năng Lv.0.
2. **Làm việc nhận tiền**: giữ E 4 giây ở *Bốc vác kho hàng* → +$12 (tiền $112), +10 XP Sức mạnh, Năng lượng −6, Độ no −4, Sạch sẽ −5, Căng thẳng +3; có toast. *Pha chế cà phê* (3 giây) → +$10, XP Giao tiếp.
3. **Lên cấp & lương**: làm 5 lượt cùng một nghề → toast "lên cấp 1"; lượt kế lương = round(12 × 1.1) = $13.
4. **Quá mệt**: hạ Năng lượng dưới 15 (làm liên tục ~15 lượt) → giữ phím báo "quá mệt", không nhận tiền/XP.
5. **Trạm miễn phí**: Tắm +40 Sạch sẽ; Giường +40 Năng lượng, −10 Căng thẳng; Ghế công viên −6 Căng thẳng, +4 Hạnh phúc. Giá trị không vượt quá 0–100.
6. **Cửa hàng**: mở bằng E; Bánh mì $10 (+30 Độ no), Phở $25 (+60 Độ no, +5 Hạnh phúc), Nước suối $5 (+8 Độ no, +5 Năng lượng); thiếu tiền → "Bạn không đủ tiền". Kính râm $200 (Nổi tiếng +5), Đồng hồ vàng $600 (+15); mua lần hai → nút "Đã sở hữu" và server từ chối. Đi xa hơn ~14 studs → cửa sổ tự đóng kèm toast.
7. **Chỉ số tụt theo thời gian** (đứng yên): mỗi phút Độ no −2, Năng lượng −1.5, Sạch sẽ −1; khi cả ba còn ≥ 30 thì Hạnh phúc +0.5/phút và Căng thẳng −0.5/phút. Khi một nhu cầu < 30: Hạnh phúc −1/phút, Căng thẳng +1/phút (mỗi nhu cầu thấp tính một lần).
8. **Kiệt sức**: đặt `Config.Stats.TimeScale = 300` rồi đứng chờ (Độ no về 0 sau ≈ 7 giây thực, kiệt sức sau ≈ 12 giây) → toast "kiệt sức", mất 10% tiền, respawn ở Spawn, chỉ số về mức an toàn (60/60/60/50/30/60). Nhớ trả `TimeScale` về `1`.
9. **Lưu/tải dữ liệu** (cần publish place và bật *Enable Studio Access to API Services*): kiếm tiền, mua Kính râm, lên cấp → Stop → Play lại: tiền, XP/level, đồ sở hữu (Nổi tiếng 5), chỉ số còn nguyên. Không bật API: Output có warn "chạy KHÔNG LƯU" và game vẫn chơi được.
10. **Chống gian lận**: từ một LocalScript thử (đặt tạm trong StarterPlayerScripts), gọi `game.ReplicatedStorage.Remotes.ShopBuy:InvokeServer("restaurant","banh_mi")` khi đứng xa → "quá xa"; gọi với tham số sai kiểu (`123`, `{}`) → "Yêu cầu không hợp lệ"; gọi dồn dập > 6 lần/3 giây → "thao tác quá nhanh".
11. **Nhiều người chơi**: mỗi người có dữ liệu, toast và cửa sổ cửa hàng riêng.

## Điều chưa làm / lưu ý

- `DataService` chưa có session locking — TODO chuyển sang ProfileStore (ghi chú trong file).
- Chưa có test tự động trong Studio; kiểm tra tự động hiện chỉ gồm biên dịch, type-check, lint và `rojo build`.
- Đã smoke-test thủ công trong Studio thật (làm nghề, trạm, mua hàng bằng chuột, tự đóng cửa sổ, kiệt sức, chống gian lận qua Remote). **Chưa kiểm chứng lưu/tải bằng DataStore thật** vì place thử chưa publish; cần bạn thử theo mục 9.
- Công cụ MCP `execute_luau` chạy trong sandbox: không `require` được module dự án và không gọi được RemoteFunction. Muốn test sâu, đặt tạm một Script/LocalScript thử vào place (đừng commit vào `src/`).
