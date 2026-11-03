#!/bin/bash
# 在普通 x86_64 Linux 上构建 ishtar 的 UEFI（SILICIUM_UEFI.fd）。
# 这里的每一步都在 aarch64 手机上验证过（见 ../../HP-TREE-REPORT.md §3/§7）；
# 在 x86_64 上，当时需要的两处宿主适配（/dev/shm、arm64 BaseTools）都不需要。
#
#   ./build.sh            # 前提：仓库根目录已把 Mu-Silicium 克隆到 hakios/BASE
#
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
MU=${MU:-$ROOT/Mu-Silicium}
BASE=$(cat "$ROOT/hakios/BASE")

[ -d "$MU" ] || { echo "build.sh: 请先把 Mu-Silicium 克隆到 $MU（BASE=$BASE）"; exit 1; }
[ "$(git -C "$MU" rev-parse HEAD)" = "$BASE" ] || { echo "build.sh: $MU 不在 BASE $BASE 上"; exit 1; }

echo "== 1. 子模块钉到 superproject 记录的提交 =="
# 用 --depth 1 取默认分支会让 Resources/MuPatches/*.patch（AsmMacroLib.patch）打不上。
git -C "$MU" submodule update --init --recursive
git -C "$MU" ls-tree HEAD -r | awk '$2=="commit"{print $3" "$4}' | while read -r sha path; do
    [ "$path" = "Binaries" ] && continue
    [ -e "$MU/$path/.git" ] || continue
    git -C "$MU/$path" fetch -q origin "$sha" && git -C "$MU/$path" checkout -q "$sha"
done

echo "== 2. 打 HakiOS 两项 hook（BootShim 的 XNUP 拷贝 + BootManagerLib 改用 XnuLoader）=="
git -C "$MU" apply --whitespace=nowarn "$ROOT/hakios/hakios.patch"
cp -r "$ROOT/hakios/files/." "$MU/"

echo "== 3. 放入 ishtar 板级包、板级配置与本机厂商二进制 =="
mkdir -p "$MU/Platforms/Xiaomi" "$MU/Binaries/ishtar"
cp -r "$ROOT/platform/ishtarPkg" "$MU/Platforms/Xiaomi/"
cp -r "$ROOT/binaries/ishtar/." "$MU/Binaries/ishtar/"
cp "$ROOT/resources/ishtar.toml" "$MU/Resources/Configs/ishtar.toml"
# 打包后处理步骤需要设备自己的设备树
# （Resources/DTBs/<device>.dtb），这是从手机上读出的 live FDT
# （/sys/firmware/fdt，902,020 B），不是手搓的。
mkdir -p "$MU/Resources/DTBs"
cp "$ROOT/dtb/ishtar.dtb" "$MU/Resources/DTBs/ishtar.dtb"

echo "== 4. Binaries 这里是普通目录，不是 Device-Binaries 子模块 =="
# 本机用的是从**本机自己的** uefi.img 抽出的驱动；公开集有
# 5 个模块不同（含携带面板初始化数据的 DisplayDxe），见 ../../uefi-ishtar/HOOK-PORT.md §6。
python3 - "$MU" <<'PY'
import sys
p = sys.argv[1] + '/Platforms/Xiaomi/ishtarPkg/DeviceBuild.py'
s = open(p).read()
s = s.replace('RequiredSubmodule ("Binaries", True)', 'RequiredSubmodule ("Binaries", False)')
s = s.replace('os.path.join(os.environ.get("UNIXNU_ROOT", os.path.join(WorkspaceRoot, "..", "UniXNU")), "package"),', '')
open(p, 'w').write(s)
PY

echo "== 5. Python 构建环境 =="
python3 -m venv "$ROOT/venv"
"$ROOT/venv/bin/pip" -q install --upgrade pip
"$ROOT/venv/bin/pip" -q install -r "$MU/pip-requirements.txt"
# shellcheck disable=SC1091
source "$ROOT/venv/bin/activate"

echo "== 6. 取外部依赖（Mu-Basetools、OneCrypto、nasm）=="
python3 -m edk2toolext.invocables.edk2_update -c "$MU/Platforms/Xiaomi/ishtarPkg/DeviceBuild.py"

echo "== 7. 执行构建 =="
cd "$MU"
python3 build_uefi.py -d ishtar -r RELEASE

FD=$(find "$MU/Build" -path '*ishtarPkg*' -name 'SILICIUM_UEFI.fd' | head -1)
[ -n "$FD" ] || { echo "build.sh: 没有产出 SILICIUM_UEFI.fd"; exit 1; }
echo "== 完成：$FD（$(stat -c %s "$FD") 字节，应等于 0x300000）=="
cp "$FD" "$ROOT/SILICIUM_UEFI-ishtar.fd"
