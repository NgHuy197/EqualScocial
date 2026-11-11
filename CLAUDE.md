# Equal Social — hướng dẫn cho Claude Code

Game Roblox nhiều người chơi, viết bằng Luau + Rojo. **Mọi chữ hiển thị trong game phải là tiếng Việt.**

> **Trước khi làm bất kỳ tính năng mới nào: đọc [docs/GDD.md](docs/GDD.md)** (tầm nhìn, công thức, số liệu, thiết kế các giai đoạn sau, câu hỏi thiết kế còn mở). Nếu thay đổi thiết kế hoặc số liệu, cập nhật cả GDD.

## Tổng quan

Một xã hội giống ngoài đời, nhưng mọi người chơi **xuất phát như nhau**: cùng tiền ($100), cùng chỉ số, không gia thế, không bệnh tật. Người chơi cạnh tranh công bằng bằng cách học skill, làm nghề, luyện tập, đấu với nhau rồi mua tài sản để khoe. Mọi tài sản thuộc sở hữu và do siêu máy tính AI **AURA** cai quản. Lối chơi giống Stardew Valley + The Sims, nhưng đề cao tương tác và cạnh tranh giữa người chơi.

Trạng thái: **v0.3** (MVP v0.1 + trường học, đánh quái, bảng xếp hạng + AURA cai quản: tài sản thuê, thuế, sự kiện, đấu giá, lạm phát; xem GDD mục 4, 6, 7). Lộ trình: v0.4 PvP + Season.

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
src/shared  → ReplicatedStorage.Shared                       Config, Remotes, Format, Types, Calendar
src/server  → ServerScriptService.Server (init.server.luau)  Services/, Util/, WorldBuilder
src/client  → StarterPlayer.StarterPlayerScripts.Client      init.client.luau, UI/
```

- `Config.luau`: **toàn bộ** số liệu cân bằng và câu chữ hiển thị (`Config.Text`).
- `Remotes.luau`: danh sách RemoteEvent/RemoteFunction. Server gọi `Remotes.Init()` một lần; nơi khác dùng `Remotes.Event(name)` / `Remotes.Function(name)`.
- `Calendar.luau`: lịch trong game thuần tính toán từ giờ server (`workspace:GetServerTimeNow()`), dùng chung server (lớp mở/đóng) và client (HUD).
- `Services/*` (thứ tự khởi động trong `init.server.luau`): `DataService`, `EconomyService`, `StatsService`, `SkillService`, `JobService`, `StationService`, `ShopService`, `SchoolService`, `CombatService`, `AssetService` (thuê/trả tài sản, phí duy trì, thu hồi), `AuctionService` (đấu giá tài sản hiếm, tiền khóa), `AuraService` (chu kỳ, thuế, sự kiện, lạm phát, Báo cáo), `LeaderboardService`, `ReplicationService`.
- `Util/*`: `Validate` (kiểm tra dữ liệu/khoảng cách), `RateLimiter`, `Prompts` (gắn ProximityPrompt theo tag có cooldown + kiểm tra khoảng cách phía server), `Describe` (chuỗi mô tả nghề/điều kiện dùng chung), `MonsterModel` (dựng quái và thanh máu), `BoardGui` (vẽ chữ lên bảng xếp hạng 3D), `AssetRegistry` (kho tài sản hiếm toàn cầu trong DataStore, nhận/trả nguyên tử bằng `UpdateAsync`; Studio không API thì dùng bản cục bộ).
- Client `UI/*`: `Theme`, `HUD`, `Toast`, `ShopWindow`, `LeaderboardWindow`, `AuraWindow` (3 tab Tài sản / Đấu giá / Báo cáo).
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
| Nghề | `ES_Job` | `JobId` | khoá trong `Config.Jobs` (`warehouse`, `barista`, `technician`, `manager`) |
| Lớp học | `ES_Class` | `ClassId` | khoá trong `Config.Classes` (`gym`, `softskills`, `library`, `workshop`) |
| Trạm | `ES_Station` | `StationId` | khoá trong `Config.Stations` (`shower`, `bed`, `bench`) |
| Cửa hàng | `ES_Shop` | `ShopId` | khoá trong `Config.Shops` (`restaurant`, `fashion`) |
| Điểm xuất hiện quái | `ES_MonsterSpawn` | `MonsterId` | khoá trong `Config.Monsters` (`slime`, `bear`); phải là `BasePart` |
| Bệnh xá | `ES_Infirmary` | (không) | nơi hồi sinh khi thua trận |
| Bảng xếp hạng 3D | `ES_Leaderboard` | (không) | `LeaderboardService` tự vẽ `SurfaceGui` lên mặt trước (-Z) |
| Trụ sở AURA | `ES_Aura` | (không) | nhấn E mở cửa sổ AURA |

Tag `ES_Monster` do `CombatService` tự gắn lên quái đang sống, không gắn tay. Nếu Workspace đã có thư mục/model tên `World`, WorldBuilder không dựng gì thêm.

## Checklist test thủ công (MVP)

Chạy trong Studio (Play, hoặc Test → 2 người chơi). Để test nhanh theo thời gian, đặt tạm `Config.Stats.TimeScale = 60` (nhớ trả về `1`).

1. **Khởi động**: Output có `[WorldBuilder] Đã dựng map placeholder: 4 nghề, 4 lớp học, 3 trạm, 2 cửa hàng, 6 điểm xuất hiện quái` và `[EqualSocial] Server đã sẵn sàng`, không có lỗi đỏ. HUD hiện **$100**, Nổi tiếng 0, "Tài sản ròng: $100 · Hạng #1", "Hôm nay: Thứ …", 6 thanh chỉ số (Độ no/Năng lượng/Sạch sẽ 100, Hạnh phúc 70, Căng thẳng 10, Sức khỏe 100), 4 kỹ năng Lv.0.
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

**Checklist v0.2** (prompt mặc định của Roblox chỉ hiện khi khối nằm trong tầm nhìn camera: hãy quay mặt về phía khối trước khi giữ E):

12. **Lịch**: dòng "Hôm nay" trên HUD đổi sang ngày kế sau mỗi 10 phút thực (7 ngày một vòng).
13. **Trường học**: ở lớp *đang mở hôm nay*, giữ E 6 giây → trừ học phí 10 × (level + 1), +30 XP, chi phí chỉ số của lớp, có toast. Ở lớp *đang nghỉ*: ngay khi bắt đầu giữ phím có toast "hôm nay nghỉ, lớp mở vào: …", không thu phí. Thiếu tiền / Năng lượng dưới 15 / kỹ năng đã tối đa → từ chối, không thu phí.
14. **Nghề mở khóa**: Kỹ thuật viên cần Khéo tay Lv3; Quản lý cần Trí tuệ Lv5 **và** Giao tiếp Lv3. Chưa đủ → toast nêu kỹ năng còn thiếu và level hiện tại, không nhận tiền; đủ → lương = gốc × (1 + 0,1 × level kỹ năng nghề).
15. **Đánh quái**: nhấn E vào Slime Kẹo (Lv0 cần 3 đòn, cách nhau ≥ 1 giây; đòn dồn dập bị bỏ qua) → +$12, +12 XP Sức mạnh, Năng lượng −6, Độ no −4, Căng thẳng +5, thanh máu quái giảm, toast "Hạ Slime Kẹo…". Đứng trong tầm 11 studs thì bị quái đánh (máu Humanoid giảm; chỉ số Sức khỏe không đổi). Quái hồi sinh sau 15 giây.
16. **Thua trận**: để quái hạ gục → toast "bị … đánh bại", mất $10 (không bao giờ âm tiền), hồi sinh ở Bệnh xá (không kiệt sức, không mất 10% tiền).
17. **Chia thưởng và trần tiền**: hai người cùng hạ Gấu Bông (mỗi người gây ≥ 10% máu) → mỗi người nhận 75% ($38, 30 XP); người chỉ đánh 1 đòn không nhận gì. Muốn thử trần nhanh: đặt tạm `Config.Combat.HourlyMoneyCap = 20` → sau khi chạm trần vẫn nhận XP, không nhận tiền, toast cảnh báo.
18. **Bảng xếp hạng**: bảng 3D ở quảng trường; nhấn E mở panel (dòng của bạn được tô nổi, chân panel ghi hạng). Không có API: panel ghi chú "chỉ gồm người chơi trong máy chủ này". Có API + publish: thoát rồi vào lại vẫn còn hạng và tài sản.
19. **Chống gian lận v0.2**: gọi `GetLeaderboard:InvokeServer()` hơn 3 lần/10 giây từ LocalScript thử → các lần vượt trả về `nil`.

**Checklist v0.3** (Trụ sở AURA ở (65, 55); chu kỳ AURA = 1 ngày game = 10 phút thực):

20. **Mở Trụ sở**: nhấn E → cửa sổ 3 tab; đi xa hơn 25 studs → tự đóng kèm toast. HUD có dòng AURA (sự kiện đang chạy hoặc "không có sự kiện").
21. **Thuê / trả**: tab Tài sản, thuê Xe máy ($800) → tiền giảm, Nổi tiếng +15, tài sản ròng tăng theo giá thuê. Thiếu tiền → từ chối, không trừ tiền. Thuê lần hai → từ chối. Trả lại → không hoàn tiền, Nổi tiếng giảm. Xe thể thao / Biệt thự không thuê trực tiếp được (chỉ qua đấu giá).
22. **Phí duy trì và thu hồi**: sang chu kỳ mới → trừ phí × hệ số chính sách, có toast. Không đủ tiền → ghi nợ và cảnh báo; nợ quá 3 chu kỳ → bị thu hồi. Không bị trừ phí cho thời gian ngoại tuyến.
23. **Thuế**: tab Báo cáo hiện thời điểm thu thuế kế tiếp và thuế dự kiến; tài sản ròng ≤ $5.000 → thuế $0; mỗi 3 chu kỳ thu thuế lũy tiến (không bao giờ âm tiền). Sự kiện "Ngày không thuế" → miễn kỳ kế tiếp.
24. **Sự kiện**: khi có "Khủng hoảng lương thực" / "Khuyến mãi đồ ăn" → giá trong Quán ăn đổi theo (×1,5 / ×0,7) cả trên cửa sổ lẫn số tiền bị trừ. "Thiếu lao động" chỉ xuất hiện khi ≥ 2 người chơi; lương nghề đó ×1,25.
25. **Đấu giá**: khi có phiên, tab Đấu giá hiện giá hiện tại, thời gian còn lại và hai nút đặt giá. Đặt giá → tiền khóa ngay + phí 2% không hoàn; bị vượt giá → hoàn ngay. Đặt giá trong 10 giây cuối → cộng 10 giây. Hết giờ → người thắng nhận tài sản hiếm (Nổi tiếng +250/+400). Người dẫn đầu rời server → phiên hủy, lần vào sau được hoàn tiền khóa.
26. **Lạm phát**: mỗi 3 chu kỳ, nếu tiền trung bình lệch mục tiêu $5.000 quá ±10% thì hệ số chính sách đổi (tối đa ±10%/lần, trong 0,5–2,0), có thông báo toàn server và dòng mới trong nhật ký Báo cáo.
27. **Chống gian lận v0.3**: gọi `AssetLease`/`AssetReturn`/`AuctionBid` với tham số sai kiểu → "Yêu cầu không hợp lệ"; khi đứng xa Trụ sở → "quá xa"; > 4 lần/5 giây → "thao tác quá nhanh"; `GetAuraState` > 3 lần/10 giây → trả `nil`. Đặt giá thấp hơn mức tối thiểu hoặc không đủ tiền → từ chối, không khóa tiền.

## Điều chưa làm / lưu ý

- `DataService` chưa có session locking — TODO chuyển sang ProfileStore (ghi chú trong file).
- Chưa có test tự động trong Studio; kiểm tra tự động hiện chỉ gồm biên dịch, type-check, lint và `rojo build`.
- Đã smoke-test thủ công trong Studio thật (làm nghề, trạm, mua hàng bằng chuột, tự đóng cửa sổ, kiệt sức, chống gian lận qua Remote). **Chưa kiểm chứng lưu/tải bằng DataStore thật** vì place thử chưa publish; cần bạn thử theo mục 9.
- Công cụ MCP `execute_luau` chạy trong sandbox: không `require` được module dự án và không gọi được RemoteFunction. Muốn test sâu, đặt tạm một Script/LocalScript thử vào place (đừng commit vào `src/`).
- v0.2 đã smoke-test trong Studio thật (học ở Xưởng, lớp đóng cửa, đánh quái, thua trận → Bệnh xá, panel bảng xếp hạng, giới hạn `GetLeaderboard`). **Chưa kiểm chứng OrderedDataStore thật** (cần publish place).
- v0.3 đã smoke-test trong Studio thật (mở Trụ sở, thuê Phòng trọ bằng chuột, phí duy trì, đặt giá và chốt phiên Xe thể thao, tab Báo cáo) với registry cục bộ; logic chu kỳ/thuế/sự kiện/lạm phát/đấu giá có harness Luau CLI ngoài repo. **Chưa kiểm chứng registry DataStore thật** (cần publish place).
- UI dựng bằng code: **đừng dựng lại cả danh sách mỗi lần snapshot/mỗi giây**, nút đang bị click sẽ bị huỷ; chỉ dựng lại khi dữ liệu đổi và cập nhật đồng hồ tại chỗ (xem `AuraWindow`).
- Chuỗi trong `Config.Text` đi qua `string.format` phải viết `%%` cho dấu phần trăm.
- Khi test tự động: prompt chỉ hiện nếu khối trong tầm nhìn camera. Đặt `workspace.CurrentCamera.CameraType = Scriptable` rồi `CFrame = CFrame.lookAt(...)` về phía khối. Khi hồi sinh, vị trí nhân vật lúc `CharacterAdded` còn ở gốc toạ độ; engine đặt vào điểm hồi sinh sau đó (xem `CombatService:_sendToInfirmary`).
