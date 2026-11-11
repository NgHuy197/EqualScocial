# Equal Social

Game Roblox nhiều người chơi: một xã hội mà **mọi người xuất phát như nhau** (cùng tiền, cùng chỉ số, không gia thế, không bệnh tật) và cạnh tranh công bằng bằng cách học skill, làm nghề, luyện tập, rồi mua tài sản để khoe. Mọi tài sản thuộc về siêu máy tính AI **AURA**. Lối chơi giống Stardew Valley + The Sims nhưng đề cao tương tác và cạnh tranh giữa người chơi.

Trạng thái: **v0.3** (MVP v0.1 + trường học, đánh quái, bảng xếp hạng + AURA cai quản tài sản). Chữ hiển thị trong game là tiếng Việt.

Tài liệu: [docs/GDD.md](docs/GDD.md) (thiết kế, công thức, lộ trình) · [CLAUDE.md](CLAUDE.md) (luật kiến trúc, checklist test cho người và Claude Code).

## Tính năng

**MVP v0.1**
- 6 chỉ số (Độ no, Năng lượng, Sạch sẽ, Hạnh phúc, Căng thẳng, Sức khỏe) tụt theo thời gian; Sức khỏe về 0 ⇒ "kiệt sức" (mất 10% tiền, respawn).
- Tiền ($100 khởi điểm), nghề kiếm tiền, kỹ năng tối đa level 20.
- 3 trạm miễn phí (Tắm, Giường, Ghế công viên), 2 cửa hàng (Quán ăn, Thời trang), chỉ số Nổi tiếng.
- Lưu dữ liệu bằng DataStore; server-authoritative; map placeholder tự dựng để nhấn Play là chơi được.

**v0.2**
- **Lịch trong game**: 10 phút thực = 1 ngày, tuần 7 ngày, hiện trên HUD.
- **Trường học** 4 lớp (Phòng gym, Lớp kỹ năng mềm, Thư viện, Xưởng thực hành) mở theo ngày; học phí = 10 × (level + 1), 30 XP mỗi buổi. Thêm 2 kỹ năng: Trí tuệ, Khéo tay.
- **Nghề mở khóa theo level**: Kỹ thuật viên (Khéo tay Lv3), Quản lý (Trí tuệ Lv5 + Giao tiếp Lv3).
- **Đánh quái** ở Bãi luyện tập (Slime Kẹo, Gấu Bông): nhấn E để đánh, chia thưởng khi đánh nhóm, trần tiền $5.000/giờ, thua trận thì trả phí và hồi sinh ở Bệnh xá.
- **Bảng xếp hạng tài sản**: bảng 3D ở quảng trường, panel top 50, hạng hiện trên HUD (OrderedDataStore; không có API thì dùng bảng cục bộ).

**v0.3**
- **Trụ sở AURA** (nhấn E): cửa sổ 3 tab Tài sản / Đấu giá / Báo cáo; chu kỳ AURA = 1 ngày game (10 phút thực).
- **Tài sản thuê** (Xe máy, Phòng trọ, Căn hộ, Ô tô): giá thuê một lần + phí duy trì mỗi chu kỳ, cộng Nổi tiếng và tài sản ròng; nợ quá 3 chu kỳ thì bị thu hồi.
- **Thuế lũy tiến** mỗi 30 phút theo tài sản ròng (0% / 1% / 3% / 6%).
- **Sự kiện ngẫu nhiên**: khủng hoảng hoặc khuyến mãi đồ ăn, thiếu lao động (+25% lương), ngày không thuế.
- **Đấu giá tài sản hiếm** (Biệt thự, Xe thể thao; kho giới hạn toàn cầu): tiền khóa khi đặt giá, phí 2%, chống chốt phút chót.
- **Bộ điều chỉnh lạm phát** công khai: hệ số chính sách 0,5–2,0 nhân vào phí và thuế, nhật ký trong tab Báo cáo.

## Cài đặt từng bước

### 1. Cài Rokit (trình quản lý công cụ)

Windows (PowerShell):

```powershell
Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
```

macOS / Linux:

```bash
curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
```

Hoặc tải `rokit.exe` từ [trang release](https://github.com/rojo-rbx/rokit/releases/latest) và chạy `rokit.exe self-install`. Sau khi cài, **mở terminal mới** để `rokit` nằm trong PATH.

### 2. Cài các công cụ của dự án

Trong thư mục dự án:

```bash
rokit install
```

Lệnh này cài **Rojo, Selene, StyLua, luau-lsp** đúng phiên bản trong [rokit.toml](rokit.toml) (Rokit sẽ hỏi xác nhận tin tưởng từng công cụ ở lần đầu).

### 3. Cài plugin Rojo cho Roblox Studio

```bash
rojo plugin install
```

Lệnh này đặt plugin vào thư mục Plugins của Studio. **Khởi động lại Studio** nếu đang mở. (Có thể thay thế bằng cách cài plugin Rojo từ Creator Store, nhưng nên dùng bản khớp phiên bản Rojo trong `rokit.toml`.)

### 4. Chạy Rojo và kết nối Studio

```bash
rojo serve
```

1. Mở Roblox Studio, tạo place mới (template **Baseplate** là được).
2. Tab **Plugins → Rojo → Connect** (mặc định `localhost:34872`).
3. Rojo đồng bộ mã nguồn vào: `src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService.Server`, `src/client` → `StarterPlayer.StarterPlayerScripts.Client`.

### 5. Bật DataStore khi test trong Studio

DataStore chỉ chạy trong Studio khi:

1. **Đã publish place**: File → *Publish to Roblox* (đặt tên, lưu vào một experience của bạn).
2. Bật **Enable Studio Access to API Services**: *Home → Game Settings → Security → Enable Studio Access to API Services*, bấm Save.

Nếu chưa làm 2 bước này, game **vẫn chạy được** nhưng ở chế độ KHÔNG LƯU và Output có cảnh báo `chạy KHÔNG LƯU`. Dữ liệu dùng key `u_<UserId>` trong DataStore `EqualSocial_PlayerData_v1`. Lưu ý: Studio ghi vào DataStore thật của experience, nên khi test hãy dùng một experience riêng cho dev.

### 6. Chơi thử

Nhấn **Play** (F5). Map placeholder tự dựng (các khối có nhãn), xung quanh điểm xuất phát ở gốc toạ độ: 4 nghề ở x = −60, 3 trạm (Vòi tắm / Giường / Ghế công viên) ở x = +60, 2 cửa hàng ở z = −70, bảng xếp hạng 3D ở z = +45, Trụ sở AURA ở (65, 55), 4 lớp học ở z = +75, Bãi luyện tập quanh z = +120 và Bệnh xá ở (−75, 120). Đến gần khối, giữ **E** để làm việc/học/dùng trạm, nhấn **E** ở cửa hàng, bảng xếp hạng, Trụ sở AURA hoặc vào quái để mở cửa sổ/đánh quái.

> Prompt **E** của Roblox chỉ hiện khi khối nằm trong tầm nhìn camera: hãy quay mặt về phía khối.

Checklist test đầy đủ ở [CLAUDE.md](CLAUDE.md#checklist-test-thủ-công-mvp).

## Thư mục

```
default.project.json   rokit.toml   selene.toml   stylua.toml
src/
  shared/   Config.luau (mọi số liệu + chữ), Remotes, Format, Types, Calendar
  server/   init.server.luau, WorldBuilder.luau, Services/ (14 service), Util/
  client/   init.client.luau, UI/ (Theme, HUD, Toast, ShopWindow, LeaderboardWindow, AuraWindow)
docs/GDD.md
```

Thêm nghề, trạm hoặc món hàng: chỉ cần sửa `src/shared/Config.luau`.

## Kiểm tra mã nguồn

```bash
stylua --check src        # định dạng (bỏ --check để tự format)
selene generate-roblox-std   # chỉ lần đầu: sinh roblox.yml
selene src                # lint
rojo build -o EqualSocial.rbxl   # kiểm tra file project
```

Type-check `--!strict` bằng luau-lsp: tải file định nghĩa API Roblox `globalTypes.d.luau` từ [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) (không commit file này), rồi:

```bash
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src
```

## Kết nối Roblox Studio MCP server (để Claude Code điều khiển Studio)

Cho phép Claude Code đọc cây đối tượng, chạy Luau, bật/tắt Play, xem Output và chụp màn hình viewport của Studio đang mở.

> ⚠️ MCP client có thể **đọc và sửa** place đang mở. Chỉ kết nối client bạn tin tưởng. Nên để **file trong `src/` là nguồn sự thật**: đừng dùng MCP sửa script mà Rojo đang đồng bộ (thay đổi sẽ bị ghi đè khi Rojo sync).

### Cách A — MCP server tích hợp sẵn trong Studio (Roblox khuyến nghị)

Repo [Roblox/studio-rust-mcp-server](https://github.com/Roblox/studio-rust-mcp-server) đã **ngừng phát triển chủ động**; Roblox chuyển sang MCP server có sẵn trong Studio ([tài liệu](https://create.roblox.com/docs/studio/mcp)).

1. Cập nhật Roblox Studio lên bản mới nhất.
2. Trong Studio mở **Assistant → … → Manage MCP Servers**, bật **Enable Studio as MCP server**.
3. Kết nối client:
   - **Quick connect**: *Assistant Settings → MCP Servers → Quick connect*, bật **Claude Code** (hoặc Claude Desktop).
   - Hoặc cấu hình JSON (Windows):
     ```json
     {
       "mcpServers": {
         "Roblox_Studio": {
           "command": "cmd.exe",
           "args": ["/c", "%LOCALAPPDATA%\\Roblox\\mcp.bat"]
         }
       }
     }
     ```
     macOS: `"command": "/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP"`.
   - Hoặc dùng CLI của Claude Code (ghép từ lệnh trong tài liệu Roblox): `claude mcp add Roblox_Studio -- cmd.exe /c "%LOCALAPPDATA%\Roblox\mcp.bat"`
4. Khởi động lại Studio và client. Kiểm tra: *Manage MCP Servers* hiện chấm xanh khi đã có client kết nối.

### Cách B — `studio-rust-mcp-server` (bản cũ trên GitHub)

1. Tải `rbx-studio-mcp.exe` (Windows) hoặc bản macOS từ [trang release](https://github.com/Roblox/studio-rust-mcp-server/releases/latest), thoát Studio và client, rồi chạy bộ cài (tự cài plugin Studio và cấu hình Claude Desktop/Cursor nếu tìm thấy).
2. Với Claude Code, thêm thủ công (theo README của repo):
   ```bash
   claude mcp add --transport stdio Roblox_Studio -- "C:\đường\dẫn\rbx-studio-mcp.exe" --stdio
   ```
   hoặc cấu hình JSON: `{"mcpServers": {"Roblox_Studio": {"command": "C:\\đường\\dẫn\\rbx-studio-mcp.exe", "args": ["--stdio"]}}}`.
3. Khởi động lại Claude Code và Studio. Trong Studio, plugin MCP xuất hiện ở tab **Plugins**; Output hiện `The MCP Studio plugin is ready for prompts.`

## Ghi chú

- Registry tài sản hiếm và lưu/tải thật chưa kiểm chứng trên place đã publish.
- Chưa có session locking cho dữ liệu (TODO chuyển sang ProfileStore).
- Robux chỉ bán cosmetic; không nội dung lãng mạn hay chính trị đời thực (xem [CLAUDE.md](CLAUDE.md) và GDD).
