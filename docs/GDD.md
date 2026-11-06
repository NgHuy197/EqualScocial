# Equal Social — Game Design Document

Phiên bản tài liệu: 0.2 (khớp bản v0.2: MVP + trường học, đánh quái, bảng xếp hạng) · Tên game tạm: **Equal Social** · AI cai quản: **AURA**

> Mọi con số trong tài liệu này là giá trị trong `src/shared/Config.luau`. Khi đổi số liệu, sửa Config **và** cập nhật bảng ở đây. Mục 4 (MVP v0.1) và mục 6 (v0.2) **đã được cài đặt**; mục 7–8 (v0.3, v0.4) là **bản nháp thiết kế**, chưa được cài đặt.

## 1. Tầm nhìn

Một xã hội thu nhỏ giống ngoài đời, nhưng **mọi người đều xuất phát như nhau**: cùng số tiền, cùng chỉ số, không gia thế, không bệnh tật. Chênh lệch chỉ đến từ lựa chọn và nỗ lực của người chơi: học kỹ năng, chọn nghề, luyện tập, đánh quái kiếm tiền, đấu với nhau, rồi mua tài sản để khoe. Toàn bộ tài sản thuộc sở hữu của siêu máy tính AI **AURA**; người chơi chỉ được thuê quyền sử dụng.

Cảm giác chơi: **Stardew Valley** (vòng lặp nhịp nhàng, nuôi dưỡng nhân vật, tiến bộ từng bước) + **The Sims** (nhu cầu cơ bản, cuộc sống thường ngày), nhưng nhấn mạnh **tương tác và cạnh tranh giữa người chơi** thay vì chơi một mình.

Lời hứa với người chơi: *"Ai cũng bắt đầu từ vạch xuất phát giống nhau, và bạn sẽ thấy ai đó giỏi hơn chỉ vì họ chơi giỏi hơn."*

## 2. Trụ cột thiết kế

1. **Bình đẳng xuất phát.** Mọi người chơi mới (và mỗi đầu mùa, từ v0.4) có dữ liệu y hệt nhau. Không có lợi thế mua bằng tiền thật.
2. **Cạnh tranh công bằng, có thể đọc được.** Mọi công thức đều đơn giản, công khai, có thể tính nhẩm (lương = gốc × (1 + 0,1 × level)). Thành công đến từ quyết định, không từ may rủi khó hiểu.
3. **Cuộc sống có nhu cầu.** Ăn, ngủ, tắm, giải tỏa căng thẳng tạo nhịp chơi và buộc người chơi cân nhắc đánh đổi giữa kiếm tiền và chăm sóc bản thân. Không có bệnh tật hay ngẫu nhiên tàn nhẫn: kiệt sức chỉ là một cú trượt dốc có thể phục hồi.
4. **Khoe được thành quả.** Tài sản, Nổi tiếng, cosmetic và bảng xếp hạng là động lực xã hội chính.
5. **AURA là luật chơi sống.** AURA sở hữu mọi tài sản, thu phí, đánh thuế, tạo sự kiện và hút tiền khỏi hệ thống để nền kinh tế không phình vô hạn. AURA là một cơ chế trung tính trong game, không phải đại diện cho chính phủ hay quan điểm chính trị thật.
6. **An toàn và đúng chính sách.** Không lãng mạn/hẹn hò, không chính trị đời thực; Robux chỉ bán cosmetic.

## 3. Vòng lặp gameplay

**Vòng lặp ngắn (vài phút):**

```
Làm nghề (giữ E) ──> nhận tiền + XP ──> chỉ số tụt (năng lượng, độ no, sạch sẽ, căng thẳng tăng)
      ^                                         │
      │                                         v
 hồi phục <── trạm miễn phí (tắm / ngủ / ghế) hoặc mua đồ ăn ──┘
```

**Vòng lặp trung (vài chục phút):** lên cấp kỹ năng → lương cao hơn → làm nhanh giàu hơn → mua đồ vĩnh viễn → Nổi tiếng tăng → khoe với người khác.

**Vòng lặp dài (nhiều ngày, từ v0.2 trở đi):** học thêm skill ở trường, đánh quái, leo bảng xếp hạng tài sản, giữ tài sản trước phí duy trì và thuế của AURA (v0.3), thi đấu PvP (v0.4), rồi **Season reset** trả mọi người về vạch xuất phát, chỉ giữ cosmetic, danh hiệu, bảng xếp hạng lịch sử.

## 4. MVP v0.1 — công thức và số liệu

### 4.1 Khởi đầu (giống nhau cho mọi người chơi)

| Mục | Giá trị |
| --- | --- |
| Tiền | $100 (`Economy.StartingMoney`) |
| Độ no / Năng lượng / Sạch sẽ | 100 / 100 / 100 |
| Hạnh phúc / Căng thẳng / Sức khỏe | 70 / 10 / 100 |
| Level kỹ năng | 0 (Sức mạnh, Giao tiếp) |
| Đồ sở hữu | không có |

### 4.2 Chỉ số (0–100)

Sáu chỉ số: **Độ no, Năng lượng, Sạch sẽ** (ba "nhu cầu"), **Hạnh phúc, Căng thẳng** (càng cao càng xấu), **Sức khỏe**. Cập nhật mỗi **5 giây** (`Stats.TickSeconds`) bằng thời gian thực đo được giữa hai tick (giới hạn ≤ 15 giây để server treo không làm chỉ số rơi tự do).

Đơn vị dưới đây là *điểm mỗi phút thực*. Hệ số `Stats.TimeScale` (mặc định 1) nhân vào tất cả để test nhanh.

| Quy tắc | Công thức |
| --- | --- |
| Độ no tụt | −2 / phút |
| Năng lượng tụt | −1,5 / phút |
| Sạch sẽ tụt | −1 / phút |
| Nhu cầu "thấp" | giá trị < 30 (`NeedLowThreshold`) |
| Với **mỗi** nhu cầu thấp | Hạnh phúc −1 / phút **và** Căng thẳng +1 / phút |
| Không nhu cầu nào thấp | Hạnh phúc +0,5 / phút **và** Căng thẳng −0,5 / phút |
| Sức khỏe: đói/kiệt sức | −3 / phút nếu Độ no ≤ 0 **hoặc** Năng lượng ≤ 0 (chỉ tính một lần) |
| Sức khỏe: căng thẳng cực độ | −1 / phút nếu Căng thẳng ≥ 90 |
| Sức khỏe: hồi phục | +1 / phút khi **không** nhu cầu nào thấp |

Các hiệu ứng sức khỏe **cộng dồn** (ví dụ Căng thẳng ≥ 90 trong khi mọi nhu cầu ổn: −1 + 1 = 0). Mọi chỉ số bị giữ trong [0, 100].

**Mốc thời gian tham khảo** (TimeScale = 1, đứng yên): Độ no xuống dưới 30 sau 35 phút, về 0 sau 50 phút; Năng lượng dưới 30 sau ≈ 46,7 phút, về 0 sau ≈ 66,7 phút; Sạch sẽ dưới 30 sau 70 phút. Khi Độ no về 0, Sức khỏe mất 3/phút nên chết đói (kiệt sức) sau ≈ 33 phút nữa.

### 4.3 Kiệt sức

Khi **Sức khỏe về 0**: người chơi **kiệt sức**.

1. Mất **10% tiền** hiện có (làm tròn xuống) qua `EconomyService.TakePercent`, lý do `exhaustion`.
2. Chỉ số reset về mức an toàn: Độ no/Năng lượng/Sạch sẽ 60, Hạnh phúc 50, Căng thẳng 30, Sức khỏe 60 (`Stats.SafeReset`).
3. Respawn tại điểm hồi sinh; hiện thông báo có số tiền bị mất.

Không có bệnh tật, không mất kỹ năng, không mất đồ.

### 4.4 Tiền

- Bắt đầu $100. Tối đa 1.000.000.000.000 (`MaxMoney`, chặn tràn số).
- `EconomyService` là nơi **duy nhất** đổi tiền: `Add(player, amount, reason)`, `TrySpend(player, amount, reason)`, `TakePercent(player, percent, reason)`. `reason` hiện có: `job`, `shop`, `exhaustion` (v0.1) và `school`, `monster`, `defeat` (v0.2). Có `OnTransaction(callback)` để AURA đánh thuế/ghi log ở v0.3.
- Số tiền luôn là số nguyên không âm.

### 4.5 Kỹ năng

| Kỹ năng | Tác dụng ở MVP |
| --- | --- |
| Sức mạnh | tăng lương *Bốc vác kho hàng* |
| Giao tiếp | tăng lương *Pha chế cà phê* |

- XP cần để lên từ level *L* lên *L+1*: **50 + 25 × L**. Tối đa **level 20**; đạt tối đa thì không tích XP thừa.
- Tổng XP để đạt level *n*: 50n + 12,5·n·(n−1). Ví dụ level 1 = 50, level 5 = 500, level 10 = 1.625, level 20 = 5.750 (575 lượt làm).
- Lên cấp (kể cả lên nhiều cấp một lúc) có thông báo.

### 4.6 Nghề (ProximityPrompt giữ phím; mỗi lần hoàn thành = một lượt làm)

| | Bốc vác kho hàng | Pha chế cà phê |
| --- | --- | --- |
| Lương gốc | $12 | $10 |
| Giữ phím | 4 giây | 3 giây |
| Kỹ năng | Sức mạnh | Giao tiếp |
| Năng lượng | −6 | −4 |
| Độ no | −4 | −3 |
| Sạch sẽ | −5 | −2 |
| Căng thẳng | +3 | +4 |

- **Lương thực nhận = lương gốc × (1 + 0,1 × level kỹ năng)**, làm tròn; level tính trước khi cộng XP của lượt đó. Kho hàng: $12 (Lv0) → $18 (Lv5) → $24 (Lv10) → $36 (Lv20). Quán cà phê: $10 → $15 → $20 → $30.
- Mỗi lượt +**10 XP**.
- **Năng lượng < 15** thì không cho làm việc (báo ngay khi bắt đầu giữ phím và khi hoàn thành).
- Cooldown phía server cho mỗi người chơi trên mỗi prompt = HoldDuration × 0,85 (chặn exploit bỏ qua thời gian giữ phím; người chơi bình thường không bị ảnh hưởng).

### 4.7 Trạm miễn phí

| Trạm | Hiệu ứng | Giữ phím |
| --- | --- | --- |
| Tắm | Sạch sẽ +40 | 3 giây |
| Giường | Năng lượng +40, Căng thẳng −10 | 5 giây |
| Ghế công viên | Căng thẳng −6, Hạnh phúc +4 | 3 giây |

(Thời gian giữ phím không có trong đề bài gốc; đây là giá trị đề xuất, có trong Config.)

### 4.8 Cửa hàng

Mở bằng ProximityPrompt (nhấn E, không cần giữ). Mua qua RemoteFunction `ShopBuy`; server chỉ chấp nhận khi người chơi còn sống và cách cửa hàng **≤ 15 studs** (`ShopRules.MaxBuyDistance`). Cửa sổ ở client tự đóng khi đi xa hơn 14 studs.

| Cửa hàng | Món | Giá | Hiệu ứng |
| --- | --- | --- | --- |
| Quán ăn | Bánh mì | $10 | Độ no +30 |
| Quán ăn | Phở | $25 | Độ no +60, Hạnh phúc +5 |
| Quán ăn | Nước suối | $5 | Độ no +8, Năng lượng +5 |
| Cửa hàng thời trang | Kính râm | $200 | Nổi tiếng +5 (sở hữu vĩnh viễn) |
| Cửa hàng thời trang | Đồng hồ vàng | $600 | Nổi tiếng +15 (sở hữu vĩnh viễn) |

- Đồ ăn dùng ngay; có thể mua dù chỉ số đã gần đầy (hiệu ứng bị giữ trong 0–100).
- Đồ thời trang **không mua trùng**; nút hiện "Đã sở hữu".
- **Nổi tiếng không được lưu**: luôn tính ra từ tổng `Fame` của các đồ đang sở hữu (MVP tối đa 20).

### 4.9 Dữ liệu và đồng bộ

- DataStore `EqualSocial_PlayerData_v1`, khoá `u_<UserId>`. Template + reconcile (người chơi cũ tự được bổ sung trường mới), `SchemaVersion = 1`.
- Tải: thử lại tối đa 4 lần. **Thất bại trên server thật ⇒ kick** để không ghi đè dữ liệu thật bằng dữ liệu rỗng. Studio không có API access ⇒ chạy **không lưu** và cảnh báo.
- Lưu: autosave mỗi 120 giây, khi rời game, và trong `BindToClose` (chờ tối đa ~25 giây). Chưa có session locking (TODO ProfileStore).
- Đồng bộ: server gom thay đổi và gửi snapshot (tiền, chỉ số, skill, đồ sở hữu, Nổi tiếng) tối đa **5 lần/giây** khi có thay đổi; client lấy trạng thái đầu bằng `GetState`. Snapshot có số thứ tự để bỏ qua gói cũ.

### 4.10 Chống gian lận (đã áp dụng trong MVP)

- Server tính tất cả; client chỉ hiển thị.
- Mọi Remote: validate kiểu/độ dài, khoảng cách, rate-limit (`GetState` 4 lần/10 giây, `ShopBuy` 6 lần/3 giây, `GetLeaderboard` 3 lần/10 giây).
- Mọi ProximityPrompt: kiểm tra người chơi còn sống, khoảng cách (kèm dung sai 6 studs), cooldown theo người chơi.
- Mua hàng: kiểm tra và ghi trong cùng một bước không yield nên không thể mua đúp bằng request song song.

### 4.11 Phân tích cân bằng MVP (nhận định, chưa kiểm chứng bằng playtest)

- Thu nhập lý thuyết tối đa ở kho hàng Lv0: một lượt tối thiểu ≈ 3,4 giây (cooldown) ⇒ ≤ 17 lượt/phút ≈ $200/phút nếu bỏ qua di chuyển và nhu cầu. Thực tế bị chặn bởi Năng lượng: một thanh đầy cho 15 lượt (≈ $180) trước khi xuống dưới 15.
- Giường hồi 40 Năng lượng chỉ trong 5 giây, miễn phí ⇒ gần như xoá giới hạn năng lượng. Giới hạn thực sự còn lại là Độ no (cần mua đồ ăn, rất rẻ so với lương) và khoảng cách đi lại. Hệ quả: **$600 cho Đồng hồ vàng có thể đạt trong vài phút**. Chấp nhận được cho MVP (phản hồi nhanh), nhưng cần cân lại khi có hút tiền của AURA (v0.3) hoặc thêm thời gian/chi phí cho trạm (xem câu hỏi mở).

## 5. Phạm vi MVP

Có trong v0.1: DataService, chỉ số, tiền, 2 nghề, 2 kỹ năng, 3 trạm, 2 cửa hàng, Nổi tiếng, replication, HUD / toast / cửa sổ cửa hàng, map placeholder.

Có thêm trong v0.2 (xem mục 6): lịch trong game, 2 kỹ năng mới (Trí tuệ, Khéo tay), trường học 4 lớp, 2 nghề mở khóa theo level (Kỹ thuật viên, Quản lý), đánh quái ở Bãi luyện tập (Slime Kẹo, Gấu Bông, Bệnh xá), bảng xếp hạng tài sản (bảng 3D + panel UI + HUD).

Chưa có: nhà/xe, AURA, PvP, Season, cosmetic bán bằng Robux, tương tác trực tiếp giữa người chơi (trao đổi, chat bubble tùy biến...).

## 6. v0.2 — Học tập, đánh quái, bảng xếp hạng (đã triển khai)

Mọi số liệu dưới đây nằm trong `src/shared/Config.luau` (`Calendar`, `School`, `Classes`, `Jobs`, `Combat`, `Monsters`, `Leaderboard`).

### 6.1 Lịch trong game

- **10 phút thực = 1 ngày game** (`Calendar.DayLengthSeconds = 600`), một tuần 7 ngày = 70 phút. Ngày 1 là Thứ Hai.
- Ngày suy ra từ **giờ server** (`workspace:GetServerTimeNow()`), không lưu dữ liệu: mọi máy chủ và mọi người chơi luôn cùng một ngày, nên người chơi gặp nhau ở lớp học theo lịch.
- HUD hiện dòng "Hôm nay: Thứ …" (client chỉ hiển thị; lớp mở hay đóng luôn do server quyết định).

### 6.2 Kỹ năng

| Kỹ năng | Học ở | Tác dụng |
| --- | --- | --- |
| Sức mạnh | Phòng gym, nghề Bốc vác, đánh quái | tăng lương Bốc vác, tăng sát thương khi đánh quái |
| Giao tiếp | Lớp kỹ năng mềm, nghề Pha chế | tăng lương Pha chế; điều kiện mở khóa Quản lý |
| **Trí tuệ** (mới) | Thư viện | tăng lương Quản lý; điều kiện mở khóa Quản lý |
| **Khéo tay** (mới) | Xưởng thực hành | tăng lương Kỹ thuật viên; điều kiện mở khóa Kỹ thuật viên |

Cùng đường cong XP (50 + 25 × level), tối đa level 20, +10% lương mỗi level. Người chơi cũ tự có thêm hai kỹ năng mới (reconcile).

### 6.3 Trường học

Mỗi buổi học = giữ phím 6 giây ở một lớp (ProximityPrompt). **Có lương? Không.** Đánh đổi: tốn tiền để lấy XP nhanh hơn làm nghề.

| Lớp | Kỹ năng | Ngày mở | Năng lượng | Độ no | Sạch sẽ | Căng thẳng |
| --- | --- | --- | --- | --- | --- | --- |
| Phòng gym | Sức mạnh | T2, T4, T6 | −10 | −5 | −6 | +2 |
| Lớp kỹ năng mềm | Giao tiếp | T3, T5, T7 | −6 | −3 | −1 | +3 |
| Thư viện | Trí tuệ | T2, T3, T5, T6 | −8 | −4 | −1 | +4 |
| Xưởng thực hành | Khéo tay | T4, T7, CN | −8 | −4 | −4 | +3 |

- **Học phí = 10 × (level kỹ năng + 1)**, tính theo level lúc bắt đầu buổi học (`School.TuitionPerLevel`), trừ qua `EconomyService` (lý do `school`). Mỗi buổi cho **30 XP** (`School.XPPerLesson`).
- Từ chối (không thu phí, báo ngay khi bắt đầu giữ phím và khi hoàn thành) nếu: lớp nghỉ hôm nay; Năng lượng dưới 15; không đủ học phí; kỹ năng đã tối đa.
- Ngày nào trong tuần cũng có ít nhất một lớp mở.

**Chi phí học từ level 0** (chỉ học ở trường, 30 XP/buổi):

| Mục tiêu | Số buổi | Học phí | Số lượt làm nghề cho cùng lượng XP |
| --- | --- | --- | --- |
| Lv1 | 2 | $20 | 5 |
| Lv3 | 8 | $170 | 22 |
| Lv5 | 17 | $580 | 50 |
| Lv10 | 55 | $3.710 | 162 |
| Lv15 | 113 | $11.340 | 337 |
| Lv20 | 192 | $25.640 | 575 |

### 6.4 Nghề mở khóa theo level

| | Kỹ thuật viên | Quản lý |
| --- | --- | --- |
| Lương gốc | $22 | $34 |
| Giữ phím | 5 giây | 5 giây |
| Kỹ năng (lương và XP) | Khéo tay | Trí tuệ |
| Điều kiện | Khéo tay Lv3 (≈ 8 buổi, $170) | Trí tuệ Lv5 **và** Giao tiếp Lv3 (≈ $750) |
| Năng lượng / Độ no / Sạch sẽ / Căng thẳng | −7 / −4 / −6 / +4 | −5 / −3 / −1 / +6 |

Nghề chưa mở khóa vẫn hiện trên map kèm "(cần …)"; làm thử sẽ báo kỹ năng còn thiếu và level hiện tại.

### 6.5 Đánh quái (Bãi luyện tập)

**Cách chơi:** đến gần quái, **nhấn E để đánh** (ProximityPrompt "Đánh"). Quái đứng yên tại điểm xuất hiện và tự đánh người chơi gần nhất trong tầm. Hạ quái nhận tiền + XP Sức mạnh.

**Người chơi:**

| Công thức | Giá trị |
| --- | --- |
| Sát thương mỗi đòn | round(10 × (1 + 0,15 × level Sức mạnh)): Lv0 = 10, Lv5 = 18, Lv10 = 25, Lv20 = 40 |
| Chu kỳ giữa hai đòn | 1,0 giây khi Năng lượng ≥ 50; chậm dần tới 2,0 giây khi Năng lượng bằng 0 |
| Tầm đánh | 10 studs (server kiểm tra lại, dung sai 2 studs) |
| Máu trong trận | máu Humanoid (100), **tách riêng** chỉ số Sức khỏe: bị đánh không gây kiệt sức |

**Quái:**

| | Slime Kẹo | Gấu Bông |
| --- | --- | --- |
| Máu | 30 | 120 |
| Sát thương / chu kỳ quái | 5 / 2,0 giây | 14 / 2,5 giây |
| Tầm đánh của quái | 11 studs | 11 studs |
| Thưởng tiền | $12 | $50 |
| XP Sức mạnh | 12 | 40 |
| Chi phí mỗi lần hạ (Năng lượng / Độ no / Căng thẳng) | −6 / −4 / +5 | −20 / −10 / +14 |
| Hồi sinh | 15 giây | 45 giây |
| Số điểm xuất hiện | 4 | 2 |

Ở Lv0, Slime cần 3 đòn (≈ 2 giây), Gấu cần 12 đòn (≈ 11 giây, nhận ≈ 70 máu). Ở Lv20: 1 đòn và 3 đòn.

**Chia thưởng khi nhiều người cùng hạ một quái:** chỉ người đã gây ≥ 10% máu tối đa của quái được tính. Mỗi người nhận thưởng gốc × max(0,25; 1 − 0,25 × (số người − 1)): 1 người 100%, 2 người 75% mỗi người, 3 người 50%, từ 4 người 25%. Phần XP chia cùng tỉ lệ (tối thiểu 1 XP).

**Trần tiền từ quái:** tối đa **$5.000 mỗi giờ** (cửa sổ 3.600 giây, `Combat.HourlyMoneyCap`). Cửa sổ lưu trong dữ liệu người chơi (`Combat = { WindowStart, Earned }`) nên thoát rồi vào lại không làm mới trần. Vượt trần vẫn nhận XP và bị trừ chi phí chỉ số, chỉ không nhận tiền.

**Thua trận:** chết trong vòng 6 giây sau khi bị quái đánh ⇒ trả **phí Bệnh xá $10** (tối đa bằng số tiền đang có, không bao giờ âm), hồi sinh tại **Bệnh xá** (xa bãi luyện tập). Không kiệt sức, không mất % tiền. Chết vì lý do khác (rơi, kiệt sức) thì hồi sinh bình thường.

### 6.6 Bảng xếp hạng tài sản

- **Tài sản ròng = tiền + tổng giá các món vĩnh viễn đang sở hữu** (đồ thời trang MVP). Hiện trên HUD kèm hạng.
- **OrderedDataStore** `EqualSocial_NetWorth_S1` (hậu tố là mùa, `Leaderboard.SeasonId`). Mỗi 180 giây (và khi rời game) ghi tài sản ròng của từng người chơi; mỗi 60 giây đọc top 50, trộn với giá trị **mới** của người đang ở server (ghi đè giá trị đã ghi vốn có thể cũ).
- **Bảng 3D** ở quảng trường hiện 10 hàng đầu; **panel UI** (nhấn E ở bảng) hiện đủ top 50, tô nổi dòng của bạn, chân panel ghi "Hạng của bạn: #N" hoặc "ngoài top 50".
- **Không có DataStore xếp hạng** (Studio chưa publish / chưa bật API): bảng chuyển sang chế độ **cục bộ** gồm người chơi đang ở server và ghi rõ điều đó.
- **Nghi vấn gian lận:** tài sản tăng hơn $20.000 trong một chu kỳ ghi ⇒ ghi cảnh báo `[Leaderboard] Nghi vấn` kèm UserId, số cũ, số mới để xem xét; **không chặn** (chưa có công cụ xử lý).
- Tên người chơi ngoài server lấy bằng `GetNameFromUserIdAsync` (tên đăng nhập) và được lưu đệm.

### 6.7 Phân tích cân bằng v0.2 (nhận định, chưa kiểm chứng bằng playtest)

- **Trường học là đổi tiền lấy thời gian.** Lv5 mất 17 buổi ≈ 100 giây và $580; làm nghề cho cùng XP mất 50 lượt ≈ 200 giây nhưng *kiếm* ≈ $600. Càng lên cao học phí càng đắt (Lv20 ≈ $25.640 cho 192 buổi) nên là nơi hút tiền lớn nhất của nền kinh tế.
- **Quái ngang nghề về tiền/giây nhưng rủi ro hơn.** Slime ≈ $12 trong ≈ 3 giây, Gấu ≈ $50 trong ≈ 12 giây (≈ $4/giây) so với Bốc vác Lv0 $3/giây, đổi lại tốn Năng lượng gấp đôi, tăng Căng thẳng mạnh và bị đánh. Thực tế bị chặn bởi Năng lượng (Gấu −20/lần).
- **Trần $5.000/giờ** chạm sau khoảng 25 phút cày Gấu liên tục. Nghề không có trần nên trần này chỉ ngăn quái trở thành nguồn thu *vô hạn*, không ngăn người chơi cày nghề.
- **Người chơi mạnh làm quái mất ý nghĩa:** thưởng cố định trong khi Lv20 hạ Slime bằng 1 đòn. Cần quái mạnh hơn cho giai đoạn sau.
- **Trạm miễn phí vẫn quá mạnh** (câu hỏi mở số 1): Giường hồi 40 Năng lượng trong 5 giây vẫn cho phép cày quái và học liên tục.

### 6.8 Hạn chế đã biết của v0.2

- Đánh quái bằng cách nhấn E liên tục (không có vũ khí, hoạt ảnh hay né tránh); quái không di chuyển.
- ProximityPrompt mặc định của Roblox **chỉ hiện khi prompt nằm trong tầm nhìn camera**; khi test bằng công cụ tự động phải quay camera về phía khối.
- Phát hiện gian lận bảng xếp hạng chỉ dừng ở cảnh báo; chưa có cơ chế gỡ khỏi bảng.
- Lưu/tải và OrderedDataStore **thật** chưa được kiểm chứng (cần publish place); logic đã được kiểm thử bằng DataStore giả.
- HUD cao hơn v0.1 (4 kỹ năng, 2 dòng mới); trên màn hình rất nhỏ panel cửa hàng/bảng xếp hạng có thể chồng lên HUD.

## 7. v0.3 — AURA cai quản (bản nháp)

### 7.1 Tài sản là quyền thuê từ AURA

- Tài sản (nhà, xe, nội thất lớn) **không bao giờ thuộc về người chơi**: người chơi mua *quyền sử dụng* từ AURA.
- Mỗi tài sản có **phí duy trì** theo chu kỳ (đề xuất: mỗi 24 phút thực = "1 ngày" trong game). Phí trừ tự động qua `EconomyService` (lý do `maintenance`).
- Không đủ tiền: AURA cảnh báo; sau **thời gian ân hạn** (đề xuất 3 chu kỳ) mà vẫn không trả thì **thu hồi** tài sản (trả về kho của AURA, có thể được đấu giá lại). Người chơi mất quyền dùng nhưng không bị phạt thêm.
- Dữ liệu: `Assets = { [assetId] = { LeasedAt, PaidUntil, FeePerCycle, Missed } }`; `Owned` của MVP (đồ thời trang) giữ nguyên là đồ cá nhân vĩnh viễn nhưng cosmetic.

### 7.2 Thuế lũy tiến người giàu

- AURA định kỳ đánh thuế theo **bậc thang tài sản ròng** (chỉ phần vượt ngưỡng của từng bậc). Ví dụ đề xuất:

| Phần tài sản ròng | Thuế suất mỗi chu kỳ |
| --- | --- |
| Đến $5.000 | 0% |
| $5.000 – $20.000 | 1% |
| $20.000 – $100.000 | 3% |
| Trên $100.000 | 6% |

- Người chơi thấy rõ biểu thuế và số thuế sắp tới (minh bạch để cảm giác "công bằng, không bất ngờ"). Lý do giao dịch `tax`.
- Thuế đi vào quỹ của AURA (bị hủy khỏi nền kinh tế) hoặc một phần dùng trả thưởng sự kiện.

### 7.3 Sự kiện ngẫu nhiên do AURA phát

- **Khủng hoảng giá**: giá một nhóm hàng tăng/giảm tạm thời (ví dụ đồ ăn ×1,5 trong 10 phút), có thông báo toàn server.
- **Thưởng nghề thiếu người**: AURA theo dõi số người đang làm từng nghề; nghề có ít người nhất được **+25% lương** trong một khoảng thời gian, khuyến khích người chơi cân bằng thị trường lao động.
- Các sự kiện khác (đề xuất): giảm giá cuối tuần, kiểm kê tài sản, "ngày không thuế".
- Sự kiện chọn ngẫu nhiên có trọng số nhưng **luôn công khai và áp dụng cho mọi người như nhau**.

### 7.4 Đấu giá tài sản hiếm

- Tài sản hiếm (số lượng giới hạn mỗi mùa) được **đấu giá** công khai: giá khởi điểm do AURA đặt, người trả cao nhất thắng, tiền thắng đấu giá **bị hủy** (hút tiền).
- Quy tắc chống thao túng: khóa tiền khi đặt giá, phí đặt giá không hoàn lại một phần nhỏ, giới hạn số phiên tham gia cùng lúc.

### 7.5 Hút tiền khỏi hệ thống (chống lạm phát)

- Các "cống thoát" tiền: phí duy trì, thuế, tiền thắng đấu giá, học phí, phí hồi sinh, phí vé đấu trường.
- AURA theo dõi **lượng tiền trung bình trên mỗi người chơi** và tỉ lệ tiền vào/ra, rồi điều chỉnh từ từ (giá đồ, phí duy trì, biểu thuế) theo hướng ổn định; mọi điều chỉnh được ghi nhật ký công khai trong một "Báo cáo của AURA".
- Giới hạn mức thay đổi mỗi lần (đề xuất ≤ 10%) để không gây sốc.

## 8. v0.4 — PvP có luật và Season (bản nháp)

### 8.1 PvP có luật

- **Đấu trường** có hàng chờ, các thể thức 1v1 và đội nhỏ, luật rõ ràng (thời gian, vật phẩm cho phép, vùng thi đấu), trọng tài là AURA. Phong cách hoạt hình, không máu me.
- **Xếp hạng**: điểm kỹ năng đấu (kiểu Elo) theo mùa. Chỉ số Sức mạnh/Năng lượng ảnh hưởng nhẹ để skill có ý nghĩa nhưng **không** quyết định tất cả (đề xuất: cân bằng để kỹ năng điều khiển quan trọng hơn chênh lệch chỉ số).
- **Vé vào cửa và quỹ giải thưởng**: người chơi đóng một khoản tiền trong game; AURA giữ lại một phần (hút tiền), phần còn lại chia cho người thắng.
- **Cá cược**: khán giả có thể đặt tiền *trong game* vào kết quả trận. Ràng buộc: chỉ dùng tiền trong game (không bao giờ liên quan đến Robux, không quy đổi ra tiền thật), theo kiểu quỹ chung tỉ lệ (không phải máy quay ngẫu nhiên), giới hạn mức đặt, và **bắt buộc rà soát chính sách Roblox về nội dung giống cờ bạc và điều chỉnh độ tuổi/giới hạn trước khi làm**. Nếu rủi ro chính sách cao, bỏ tính năng này.

### 8.2 Season

- Mỗi **mùa kéo dài 4–8 tuần**. Hết mùa, mọi người **quay về vạch xuất phát**:
  - **Reset**: tiền (về $100), chỉ số, kỹ năng, mọi tài sản thuê từ AURA, đồ mua bằng tiền game.
  - **Giữ lại**: cosmetic (kể cả mua bằng Robux), **danh hiệu** theo thành tích mùa, huy hiệu, và **bảng xếp hạng lịch sử** (hạng cuối mùa, tài sản ròng đỉnh, hạng PvP).
- Khuyến khích quay lại: phần thưởng cuối mùa (danh hiệu, cosmetic giới hạn), thông báo đếm ngược, "đêm chung kết" với công bố kết quả.
- Dữ liệu tách hai tầng: `Persistent` (cosmetic, danh hiệu, lịch sử) và `Season` (tiền, chỉ số, kỹ năng, tài sản). Khi vào game, nếu `Season.Id` khác mùa hiện tại thì lưu hồ sơ mùa cũ vào lịch sử, rồi dựng lại `Season` từ template. Dùng `SchemaVersion` + migration để làm việc này an toàn.
- Người chơi vào giữa mùa vẫn xuất phát bằng template chuẩn; nên có cơ chế "bắt kịp" nhẹ để họ không bị bỏ xa (xem câu hỏi mở).

### 8.3 Monetization (cosmetic-only)

- Bán bằng Robux: skin, bộ đồ, emote, hiệu ứng bước chân, khung tên, thú cưng *chỉ để trang trí*.
- **Không** bán: tiền trong game, XP, kỹ năng, chỉ số, tài sản, thứ làm tăng thu nhập hay thắng PvP, hộp ngẫu nhiên có trả phí.
- Cosmetic mua bằng Robux **không** cộng Nổi tiếng (Nổi tiếng chỉ đến từ tài sản mua bằng tiền game) để tiền thật không mua được địa vị trong cuộc cạnh tranh.

## 9. Ràng buộc nội dung (Roblox Community Standards)

- Không lãng mạn / hẹn hò: không hôn, nắm tay, cưới hỏi, ghép đôi tình cảm. Tương tác xã hội chỉ ở mức bạn bè, đồng nghiệp, đối thủ.
- Không chính trị đời thực: không đảng phái, bầu cử, nhân vật hay sự kiện chính trị thật. AURA và thuế chỉ là cơ chế hư cấu trong game.
- Không bạo lực máu me; chiến đấu hoạt hình.
- Mọi văn bản người chơi nhập đi qua bộ lọc của Roblox.
- Rà lại chính sách khi thêm: cá cược (8.1), đấu giá, bất cứ thứ gì dùng Robux.

## 10. Câu hỏi thiết kế còn mở

1. **Trạm miễn phí quá mạnh?** Giường hồi 40 Năng lượng chỉ trong 5 giây, không phí. Có nên thêm cooldown riêng cho từng trạm, giới hạn số lần/giờ, hay thời gian ngủ dài hơn?
2. **Nhịp thời gian.** Chỉ số tụt hết trong 35–70 phút thực. Với người chơi phiên ngắn (10–15 phút), chỉ số hầu như không đổi. Có cần "thời gian trôi nhanh hơn" hoặc tách thời gian ngoại tuyến?
3. **Chỉ số khi ngoại tuyến.** MVP lưu nguyên chỉ số lúc rời game. Có nên tụt nhẹ theo thời gian vắng mặt (và giới hạn mức tụt) để tránh bỏ game sạch nhưng vẫn không quá phạt?
4. **Xuất phát thật sự công bằng?** Level kỹ năng bắt đầu 0 ở mọi người. Người chơi vào giữa mùa cần bắt kịp thế nào mà không phá cảm giác công bằng (đường tắt học nhanh, thưởng "người mới")?
5. **Cân bằng nghề.** Hai nghề hiện chỉ khác lương/chi phí. Làm sao để mỗi nghề có "cá tính" (rủi ro, nhịp, tương tác xã hội) thay vì chỉ là con số?
6. **Tương tác người chơi.** Ngoài bảng xếp hạng và PvP, MVP chưa có tương tác trực tiếp. Có nên thêm hợp tác (làm chung ca kho hàng cho thưởng cao), thương mại giữa người chơi, hay hội nhóm?
7. **Giá trị của Nổi tiếng.** Hiện chỉ là con số hiển thị. Nổi tiếng nên mở khóa gì (cửa hàng cao cấp, nghề, vị trí trên bảng) mà không tạo lợi thế kiếm tiền quá lớn?
8. **Nổi tiếng và đồ thuê.** Với v0.3, nhà/xe thuê có cộng Nổi tiếng không? Nếu đồ thuê bị thu hồi thì Nổi tiếng giảm lại, có gây cảm giác bị phạt quá nặng không?
9. **Cơ chế thu hồi.** Ân hạn bao lâu là hợp lý? Có cho "cứu" bằng khoản vay từ AURA (có lãi) hay không?
10. **Thuế tính trên gì.** Tài sản ròng (khuyến khích chi tiêu) hay thu nhập (khuyến khích tích lũy)? Người chơi cố ý "giấu" tài sản bằng cách mua đồ sở hữu vĩnh viễn thì xử lý ra sao?
11. **Cá cược PvP.** Có đáng làm không so với rủi ro chính sách? Có phương án thay thế (cược bằng điểm danh vọng không có giá trị kinh tế)?
12. **Độ dài mùa.** 4 tuần hay 8 tuần? Có nên linh hoạt theo hoạt động của người chơi? Cách thông báo và kết thúc mùa để không gây hụt hẫng.
13. **Chống đa tài khoản / farm.** Cần cơ chế gì để một người dùng nhiều tài khoản chuyển tiền cho tài khoản chính? (MVP chưa có chuyển tiền; khi thêm thương mại/đấu giá phải giải quyết.)
14. **Đánh quái và PvP: chỉ số hay kỹ năng điều khiển?** Mức ảnh hưởng của chỉ số nên là bao nhiêu để người chơi mới vẫn có cơ hội thắng?
15. **Dữ liệu và scale.** Khi nào chuyển sang ProfileStore (session locking)? OrderedDataStore hay MemoryStore cho bảng xếp hạng theo thời gian thực?
16. **Cosmetic và Nổi tiếng** (đã đề xuất không cộng): chấp nhận được với người chơi mua cosmetic không? Có cần hệ "Phong cách" riêng để khoe cosmetic?
17. **Tên game.** "Equal Social" chỉ là tên tạm.
18. **Trần tiền từ quái ($5.000/giờ).** Nghề không có trần nên trần này chỉ chặn quái thành nguồn thu vô hạn. Con số phù hợp là bao nhiêu? Có nên đặt trần chung cho mọi nguồn thu thay vì riêng quái?
19. **Điều khiển đánh quái.** Hiện chỉ nhấn E nên "kỹ năng điều khiển" gần như không có. Có đáng làm vũ khí/né tránh (Tool, hoạt ảnh) hay giữ đơn giản và để chỉ số/kỹ năng quyết định?
20. **Quái đứng yên và thưởng cố định.** Người chơi Lv cao hạ quái trong 1–3 đòn. Cần quái mạnh dần, quái di chuyển hoặc thưởng tăng theo cấp bãi luyện tập?
21. **Học phí cao ở level cao.** Lv20 tốn ≈ $25.640 qua trường học, làm nghề thì miễn phí nhưng chậm hơn khoảng 2 lần. Đây có phải đánh đổi mong muốn, hay cần giảm hệ số học phí?
22. **Lịch lớp học.** Lớp chỉ mở 3–4 ngày/tuần (70 phút thực/tuần). Người chơi vào sai ngày có thấy bị chặn không? Có cần hiện đếm ngược tới ngày lớp mở?
23. **Gian lận bảng xếp hạng.** Hiện chỉ ghi cảnh báo. Khi nào cần cơ chế gỡ người chơi khỏi bảng hoặc khoá tài khoản nghi vấn?
