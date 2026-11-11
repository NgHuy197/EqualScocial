# Equal Social — hướng dẫn cho Claude Code

Game Roblox nhiều người chơi, viết bằng Luau + Rojo. **Mọi chữ hiển thị trong game phải là tiếng Việt.**

> **Trước khi làm bất kỳ tính năng mới nào: đọc [docs/GDD.md](docs/GDD.md)** (tầm nhìn, công thức, số liệu, thiết kế các giai đoạn sau, câu hỏi thiết kế còn mở). Nếu thay đổi thiết kế hoặc số liệu, cập nhật cả GDD.

## Tổng quan

Một xã hội giống ngoài đời, nhưng mọi người chơi **xuất phát như nhau**: cùng tiền ($100), cùng chỉ số, không gia thế, không bệnh tật. Người chơi cạnh tranh công bằng bằng cách học skill, làm nghề, luyện tập, đấu với nhau rồi mua tài sản để khoe. Mọi tài sản thuộc sở hữu và do siêu máy tính AI **AURA** cai quản. Lối chơi giống Stardew Valley + The Sims, nhưng đề cao tương tác và cạnh tranh giữa người chơi.

Trạng thái: **v0.5** (v0.4 + làm ca chung, thu hồi tài sản hiếm khi vắng mặt, bắt kịp giữa mùa, cosmetic Game Pass; xem GDD mục 4, 6, 7, 8). Cá cược PvP đã bị bỏ vì Roblox cấm cờ bạc mô phỏng (GDD 8.0).

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
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --ignore="**/Vendor/**" src
```

Test logic (harness chạy service thật trên Luau CLI với môi trường Roblox giả lập; cần Python 3 và [Luau CLI](https://github.com/luau-lang/luau/releases)):

```bash
python tests/build_tests.py          # ghép src + tests/harness.luau -> tests/out/test_all.luau
luau tests/out/test_all.luau         # in "KẾT QUẢ: x đạt, y lỗi", thoát mã 1 nếu có lỗi
```

Sau mỗi thay đổi code, tối thiểu phải qua: `stylua --check src`, `selene src`, type-check luau-lsp (không lỗi) và harness (0 lỗi). CI (`.github/workflows/ci.yml`) chạy đủ các bước này cho mỗi PR. Thêm tính năng phía server thì thêm nhóm kiểm tra vào `tests/harness.luau`.

## Cấu trúc

```
src/shared  → ReplicatedStorage.Shared                       Config, Remotes, Format, Types, Calendar
src/server  → ServerScriptService.Server (init.server.luau)  Services/, Util/, Vendor/, WorldBuilder
src/client  → StarterPlayer.StarterPlayerScripts.Client      init.client.luau, UI/
```

- `Config.luau`: **toàn bộ** số liệu cân bằng và câu chữ hiển thị (`Config.Text`).
- `Remotes.luau`: danh sách RemoteEvent/RemoteFunction. Server gọi `Remotes.Init()` một lần; nơi khác dùng `Remotes.Event(name)` / `Remotes.Function(name)`.
- `Calendar.luau`: lịch trong game thuần tính toán từ giờ server (`workspace:GetServerTimeNow()`), dùng chung server (lớp mở/đóng) và client (HUD).
- `Services/*` (thứ tự khởi động trong `init.server.luau`): `DataService`, `EconomyService`, `StatsService`, `SkillService`, `JobService`, `StationService`, `ShopService`, `SchoolService`, `CombatService`, `AssetService` (thuê/trả tài sản, phí duy trì, thu hồi), `AuctionService` (đấu giá tài sản hiếm, tiền khóa), `AuraService` (chu kỳ, thuế, sự kiện, lạm phát, Báo cáo), `SeasonService` (thông báo sang mùa, phần Season của snapshot), `PvpService` (hàng chờ, trận 1v1, Elo), `CosmeticService` (Game Pass bảng tên màu, gắn danh hiệu, bảng tên trên đầu), `LeaderboardService`, `ReplicationService`. `DataService` có thêm `OnReleasing(cb)` (chạy đồng bộ trước khi dữ liệu người rời game bị gỡ) và `TakeRollover(player)`.
- `Vendor/ProfileStore`: thư viện ProfileStore (MAD STUDIO, Apache 2.0) giữ **nguyên bản gốc**, không sửa; nguồn và commit ghi trong `SOURCE.txt`. Được loại khỏi StyLua (`.styluaignore`), Selene (`exclude` trong `selene.toml`) và type-check (`--ignore`). Chỉ `DataService` require nó.
- `Util/*`: `Validate` (kiểm tra dữ liệu/khoảng cách), `RateLimiter`, `Prompts` (gắn ProximityPrompt theo tag có cooldown + kiểm tra khoảng cách phía server), `Describe` (chuỗi mô tả nghề/điều kiện dùng chung), `MonsterModel` (dựng quái và thanh máu), `BoardGui` (vẽ chữ lên bảng xếp hạng 3D), `AssetRegistry` (kho tài sản hiếm toàn cầu trong DataStore, nhận/trả nguyên tử bằng `UpdateAsync`; Studio không API thì dùng bản cục bộ), `Season` (logic thuần sang mùa: lưu lịch sử, trao danh hiệu, reset về template), `NameTag` (dựng BillboardGui bảng tên trên đầu nhân vật; harness thay bằng bản giả).
- Client `UI/*`: `Theme`, `HUD`, `Toast`, `ShopWindow`, `LeaderboardWindow`, `AuraWindow` (3 tab Tài sản / Đấu giá / Báo cáo), `ProfileWindow` (Hồ sơ: danh hiệu + nút gắn, bảng tên màu + nút mua/dùng, lịch sử mùa, thưởng bắt kịp; mở bằng nút trên HUD hoặc phím P).
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
| Quầy Đấu trường | `ES_Arena` | (không) | nhấn E vào / rời hàng chờ |
| Bục xuất phát | `ES_ArenaPad` | `PadIndex` | `1` hoặc `2`; tâm đấu trường = trung điểm hai bục |

Tag `ES_Monster` do `CombatService` tự gắn lên quái đang sống, không gắn tay. Nếu Workspace đã có thư mục/model tên `World`, WorldBuilder không dựng gì thêm.

## Checklist test thủ công (MVP)

Chạy trong Studio (Play, hoặc Test → 2 người chơi). Để test nhanh theo thời gian, đặt tạm `Config.Stats.TimeScale = 60` (nhớ trả về `1`).

1. **Khởi động**: Output có `[WorldBuilder] Đã dựng map placeholder: 4 nghề, 4 lớp học, 3 trạm, 2 cửa hàng, 6 điểm xuất hiện quái` và `[EqualSocial] Server đã sẵn sàng`, không có lỗi đỏ. HUD hiện **$100**, Nổi tiếng 0, "Tài sản ròng: $100 · Hạng #1", "Hôm nay: Thứ …", 6 thanh chỉ số (Độ no/Năng lượng/Sạch sẽ 100, Hạnh phúc 70, Căng thẳng 10, Sức khỏe 100), 4 kỹ năng Lv.0.
2. **Làm việc nhận tiền**: giữ E 4 giây ở *Bốc vác kho hàng* → +$12 (tiền $112), +10 XP Sức mạnh, Năng lượng −6, Độ no −4, Sạch sẽ −5, Căng thẳng +3; có toast. *Pha chế cà phê* (3 giây) → +$10, XP Giao tiếp.
3. **Lên cấp & lương**: làm 5 lượt cùng một nghề → toast "lên cấp 1"; lượt kế lương = round(12 × 1.1) = $13.
4. **Quá mệt**: hạ Năng lượng dưới 15 (làm liên tục ~15 lượt) → giữ phím báo "quá mệt", không nhận tiền/XP.
5. **Trạm miễn phí**: Tắm +40 Sạch sẽ; Giường +40 Năng lượng, −10 Căng thẳng; Ghế công viên −6 Căng thẳng, +4 Hạnh phúc. Giá trị không vượt quá 0–100. Dùng lại cùng trạm trước cooldown (Tắm 2 phút, Giường 3 phút, Ghế 45 giây) → toast "cần chờ thêm …", không có tác dụng; thoát ra vào lại vẫn còn cooldown.
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

**Checklist v0.4** (Đấu trường ở (0, −125), quầy ở (0, −89); trận cần **Test → 2 người chơi**):

28. **HUD mùa**: dòng "Mùa 1 · còn … ngày · PvP 1000 điểm".
29. **Hàng chờ**: nhấn E ở quầy → toast "vào hàng chờ", HUD "Đấu trường: đang chờ ghép cặp"; nhấn lần nữa → rời. Năng lượng < 20 → từ chối.
30. **Trận**: hai người vào hàng chờ → dịch chuyển lên hai bục, đếm ngược 3 giây, HUD hiện máu hai bên và thời gian; F (hoặc nút "Đánh") khi trong 10 studs → đối thủ −10 máu, tối đa 1 đòn/giây. Máu nhân vật không đổi, không mất tiền.
31. **Luật**: hạ gục → thắng (+16 / −16 khi ngang điểm); ra xa tâm > 34 studs → thua; hết 60 giây → nhiều máu hơn thắng, bằng máu → hòa; một người thoát game → người kia thắng. Sau trận cả hai về cạnh quầy, Năng lượng −10, Căng thẳng +8, có XP Sức mạnh.
32. **Sang mùa** (place thử): tăng tạm `Config.Season.Id` lên 2 → vào game: toast chào Mùa 2, tiền $100, kỹ năng/đồ/tài sản/PvP reset, danh hiệu (nếu đạt) xuất hiện trên HUD. Trả `Id` về 1 (dữ liệu thử đã sang mùa 2 sẽ được coi là mùa khác và bị reset lần nữa, nên chỉ thử trên dữ liệu dev).
33. **Chống gian lận v0.4**: `PvpAttack:FireServer()` khi không trong trận → không có gì; dồn dập → bị rate-limit, không lỗi. `GetProfile:InvokeServer()` hơn 3 lần/10 giây → các lần vượt trả về `nil`.
33a. **Ghép cặp theo điểm** (3 người chơi trở lên): chênh lệch lớn chỉ được ghép sau khi chờ đủ lâu (100 + 10 × giây chờ); đang có trận thì người khác tiếp tục chờ, không bị dịch chuyển lên bục.
33b. **Hồ sơ**: nhấn P hoặc nút "Hồ sơ [P]" → cửa sổ hiện điểm PvP, thắng/thua/hòa, tài sản ròng cao nhất, danh hiệu và các mùa trước; nút Đóng bấm được; mở Hồ sơ thì cửa sổ khác tự đóng.

**Checklist v0.5:**

33c. **Làm ca chung** (Test → 2–3 người chơi): cùng giữ E ở *Bốc vác kho hàng* trong vòng 20 giây → người hoàn thành sau nhận $13 thay vì $12 (Lv0, 1 người làm chung), toast ghi "làm chung với 1 người (+10% lương)"; tối đa +30%. Nghề khác hoặc chỗ làm cách > 40 studs không tính.
33d. **Bảng tên**: trên đầu nhân vật hiện tên (không còn tên mặc định của Roblox). Gắn danh hiệu trong Hồ sơ → dòng thứ hai hiện danh hiệu; "Gỡ" → mất dòng đó. Hồi sinh vẫn còn bảng tên.
33e. **Cosmetic**: trong Hồ sơ ba bảng tên màu hiện "Sắp ra mắt" khi `GamePassId = 0`. Đặt ID Game Pass thật (place đã publish) → nút "Mua" mở hộp thoại Roblox; mua xong → toast cảm ơn, nút thành "Dùng"; "Dùng" → bảng tên đổi màu; vào lại vẫn giữ. Cosmetic không đổi Nổi tiếng.
33f. **Bắt kịp**: đặt tạm `Config.Season.StartsAt` lùi 3 tuần → vào game có toast "+30% XP trong 3 giờ chơi đầu"; một lượt Bốc vác cho 13 XP thay vì 10; Hồ sơ hiện dòng thưởng. Trả `StartsAt` về như cũ.
33g. **Tài sản hiếm vắng mặt** (cần publish, hoặc kiểm tra bằng harness): chủ không vào game quá 7 ngày và có người khác thắng đấu giá suất đó → khi chủ cũ vào lại, toast "vắng mặt quá 7 ngày", tài sản biến mất.

**Kiểm chứng sau khi publish** (cần bạn: File → Publish to Roblox, bật *Enable Studio Access to API Services*, dùng experience dev):

34. **ProfileStore**: Output có `[ProfileStore]: Roblox API services available - data will be saved`, không có warn "KHÔNG LƯU". Kiếm tiền, mua Kính râm → Stop → Play: còn nguyên (mục 9).
35. **Khóa phiên**: publish rồi vào game thật bằng 2 thiết bị / 2 server (hoặc vào server A rồi nhảy sang server B ngay): server B chờ tối đa ~40 giây rồi mới tải, dữ liệu là bản server A vừa lưu; không bao giờ có hai bản cùng chạy.
36. **Bảng xếp hạng thật**: panel không còn ghi "chỉ gồm người chơi trong máy chủ này"; hạng còn sau khi vào lại.
37. **Registry tài sản hiếm**: tab Báo cáo không còn ghi registry cục bộ; thắng đấu giá ở server A → số còn lại giảm ở server B (sau tối đa 30 giây cache).

## Điều chưa làm / lưu ý

- `DataService` dùng ProfileStore (khóa phiên): người chơi vào server mới khi server cũ chưa nhả khóa sẽ chờ tối đa ~40 giây; bị server khác giành phiên khi đang chơi thì bị kick (`DataSessionEnded`). Store `EqualSocial_PlayerData_v2` (định dạng ProfileStore); store v1 cũ không được đọc lại (place chưa từng publish nên không có dữ liệu thật). **Chưa kiểm chứng khóa phiên giữa hai server thật** (cần publish và vào 2 server).
- Chưa có test tự động **trong Studio**; harness `tests/` (chạy cả trong CI) kiểm tra logic server/shared với Roblox giả lập, không kiểm tra UI client hay hành vi engine thật.
- Đã smoke-test thủ công trong Studio thật (làm nghề, trạm, mua hàng bằng chuột, tự đóng cửa sổ, kiệt sức, chống gian lận qua Remote). **Chưa kiểm chứng lưu/tải bằng DataStore thật** vì place thử chưa publish; cần bạn thử theo mục 9.
- Công cụ MCP `execute_luau` chạy trong sandbox: không `require` được module dự án và không gọi được RemoteFunction. Muốn test sâu, đặt tạm một Script/LocalScript thử vào place (đừng commit vào `src/`).
- v0.2 đã smoke-test trong Studio thật (học ở Xưởng, lớp đóng cửa, đánh quái, thua trận → Bệnh xá, panel bảng xếp hạng, giới hạn `GetLeaderboard`). **Chưa kiểm chứng OrderedDataStore thật** (cần publish place).
- v0.3 đã smoke-test trong Studio thật (mở Trụ sở, thuê Phòng trọ bằng chuột, phí duy trì, đặt giá và chốt phiên Xe thể thao, tab Báo cáo) với registry cục bộ; logic chu kỳ/thuế/sự kiện/lạm phát/đấu giá có harness (`tests/`). **Chưa kiểm chứng registry DataStore thật** (cần publish place).
- v0.4 đã smoke-test trong Studio (map Đấu trường, dòng Mùa trên HUD, vào/rời hàng chờ, cooldown Giường) nhưng **trận 1v1 chưa chạy với 2 người chơi thật** (MCP chỉ điều khiển một client); logic trận, Elo, luật kết thúc, thoát giữa trận và sang mùa có harness. Hãy chạy mục 30–31 bằng Test → 2 người chơi.
- UI dựng bằng code: **đừng dựng lại cả danh sách mỗi lần snapshot/mỗi giây**, nút đang bị click sẽ bị huỷ; chỉ dựng lại khi dữ liệu đổi và cập nhật đồng hồ tại chỗ (xem `AuraWindow`).
- Chuỗi trong `Config.Text` đi qua `string.format` phải viết `%%` cho dấu phần trăm.
- Khi test tự động: prompt chỉ hiện nếu khối trong tầm nhìn camera. Đặt `workspace.CurrentCamera.CameraType = Scriptable` rồi `CFrame = CFrame.lookAt(...)` về phía khối. Khi hồi sinh, vị trí nhân vật lúc `CharacterAdded` còn ở gốc toạ độ; engine đặt vào điểm hồi sinh sau đó (xem `CombatService:_sendToInfirmary`).
