"""Ghép mã nguồn THẬT của dự án + harness thành một file Luau chạy được bằng Luau CLI.

Harness (tests/harness.luau) giả lập môi trường Roblox (Players, DataStore, ProfileStore, Remote,
CollectionService...) rồi chạy các service phía server và shared. Client và WorldBuilder không được
nạp vì dùng Instance thật.

Chạy (từ thư mục gốc dự án):
    python tests/build_tests.py
    luau tests/out/test_all.luau

Tham số tuỳ chọn: <thư mục src> <file harness> <file đầu ra>.
Chỉ đọc file dự án; file đầu ra nằm trong tests/out/ (đã .gitignore).
"""
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
src_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "src"
body_path = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else root / "tests" / "harness.luau"
out = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else root / "tests" / "out" / "test_all.luau"

body = body_path.read_text(encoding="utf-8")

# Chỉ nạp server + shared. ProfileStore (Vendor) được harness thay bằng bản giả có khóa phiên.
skip_names = {"init.server.luau", "init.client.luau", "WorldBuilder.luau"}
entries = []
for path in sorted(src_dir.rglob("*.luau")):
    rel = path.relative_to(src_dir).as_posix()
    if rel.startswith("client/") or rel.startswith("server/Vendor/") or path.name in skip_names:
        continue
    key = rel[: -len(".luau")]
    text = path.read_text(encoding="utf-8")
    delimiter = "]=====]"
    assert delimiter not in text, f"{rel} chứa chuỗi đóng long-bracket"
    entries.append(f'\t["{key}"] = [=====[{text}{delimiter},')

header = "local SOURCES = {\n" + "\n".join(entries) + "\n}\n\n"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(header + body, encoding="utf-8")
print(f"OK: ghép {len(entries)} module -> {out}")
