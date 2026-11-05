# Equal Social

Game Roblox nhiều người chơi: một xã hội mà **mọi người xuất phát như nhau** (cùng tiền, cùng chỉ số, không gia thế, không bệnh tật) và cạnh tranh công bằng bằng cách học skill, làm nghề, luyện tập, rồi mua tài sản để khoe. Mọi tài sản thuộc về siêu máy tính AI **AURA**. Lối chơi giống Stardew Valley + The Sims nhưng đề cao tương tác và cạnh tranh giữa người chơi.

Trạng thái: **MVP v0.1**. Chữ hiển thị trong game là tiếng Việt.

Tài liệu: [docs/GDD.md](docs/GDD.md) (thiết kế, công thức, lộ trình) · [CLAUDE.md](CLAUDE.md) (luật kiến trúc, checklist test cho người và Claude Code).

## Tính năng MVP

- 6 chỉ số (Độ no, Năng lượng, Sạch sẽ, Hạnh phúc, Căng thẳng, Sức khỏe) tụt theo thời gian; Sức khỏe về 0 ⇒ "kiệt sức" (mất 10% tiền, respawn).
- Tiền ($100 khởi điểm), 2 nghề (Bốc vác kho hàng, Pha chế cà phê) với 2 kỹ năng (Sức mạnh, Giao tiếp), tối đa level 20.
- 3 trạm miễn phí (Tắm, Giường, Ghế công viên), 2 cửa hàng (Quán ăn, Thời trang), chỉ số Nổi tiếng.
- Lưu dữ liệu bằng DataStore; server-authoritative; map placeholder tự dựng để nhấn Play là chơi được.

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

Nhấn **Play** (F5). Map placeholder tự dựng (các khối có nhãn): Kho hàng và Quán cà phê (bên trái), Vòi tắm / Giường / Ghế công viên (bên phải), Quán ăn và Cửa hàng thời trang (phía trước). Đến gần khối, giữ **E** để làm việc/dùng trạm, nhấn **E** ở cửa hàng để mở cửa sổ mua đồ.

Checklist test đầy đủ ở [CLAUDE.md](CLAUDE.md#checklist-test-thủ-công-mvp).

## Thư mục

```
default.project.json   rokit.toml   selene.toml   stylua.toml
src/
  shared/   Config.luau (mọi số liệu + chữ), Remotes, Format, Types
  server/   init.server.luau, WorldBuilder.luau, Services/, Util/
  client/   init.client.luau, UI/ (Theme, HUD, Toast, ShopWindow)
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

- Chưa có session locking cho dữ liệu (TODO chuyển sang ProfileStore).
- Robux chỉ bán cosmetic; không nội dung lãng mạn hay chính trị đời thực (xem [CLAUDE.md](CLAUDE.md) và GDD).
