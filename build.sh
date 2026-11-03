#!/bin/bash
# Build ishtar's UEFI (SILICIUM_UEFI.fd) on a normal x86_64 Linux host.
# Everything here was validated on the aarch64 phone itself (see ../HP-TREE-REPORT.md §3/§7);
# on x86_64 the two host workarounds that were needed there (/dev/shm, arm64 BaseTools) do not apply.
#
#   ./build.sh            # expects Mu-Silicium/ cloned at hakios/BASE at the repository root
#
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
MU=${MU:-$ROOT/Mu-Silicium}
BASE=$(cat "$ROOT/hakios/BASE")

[ -d "$MU" ] || { echo "build.sh: clone Mu-Silicium at $BASE into $MU first"; exit 1; }
[ "$(git -C "$MU" rev-parse HEAD)" = "$BASE" ] || { echo "build.sh: $MU is not at BASE $BASE"; exit 1; }

echo "== 1. submodules pinned to the superproject's recorded commits =="
# A --depth 1 checkout of a default branch breaks Resources/MuPatches/*.patch (AsmMacroLib.patch).
git -C "$MU" submodule update --init --recursive
git -C "$MU" ls-tree HEAD -r | awk '$2=="commit"{print $3" "$4}' | while read -r sha path; do
    [ "$path" = "Binaries" ] && continue
    [ -e "$MU/$path/.git" ] || continue
    git -C "$MU/$path" fetch -q origin "$sha" && git -C "$MU/$path" checkout -q "$sha"
done

echo "== 2. HakiOS hooks (two hooks: BootShim XNUP copy + BootManagerLib -> XnuLoader) =="
git -C "$MU" apply --whitespace=nowarn "$ROOT/hakios/hakios.patch"
cp -r "$ROOT/hakios/files/." "$MU/"

echo "== 3. ishtar platform, board config and the device's own vendor binaries =="
mkdir -p "$MU/Platforms/Xiaomi" "$MU/Binaries/ishtar"
cp -r "$ROOT/platform/ishtarPkg" "$MU/Platforms/Xiaomi/"
cp -r "$ROOT/binaries/ishtar/." "$MU/Binaries/ishtar/"
cp "$ROOT/resources/ishtar.toml" "$MU/Resources/Configs/ishtar.toml"
# The post-build step wants the device's own device tree next to the image
# (Resources/DTBs/<device>.dtb). This is the live FDT read off the phone
# (/sys/firmware/fdt, 902,020 B), not a hand-made one.
mkdir -p "$MU/Resources/DTBs"
cp "$ROOT/dtb/ishtar.dtb" "$MU/Resources/DTBs/ishtar.dtb"

echo "== 4. Binaries is a plain directory here, not the Device-Binaries submodule =="
# This port uses the drivers extracted from *this unit's* uefi.img; the public set differs in
# 5 modules including DisplayDxe (panel init data). See ../uefi-ishtar/HOOK-PORT.md §6.
python3 - "$MU" <<'PY'
import sys
p = sys.argv[1] + '/Platforms/Xiaomi/ishtarPkg/DeviceBuild.py'
s = open(p).read()
s = s.replace('RequiredSubmodule ("Binaries", True)', 'RequiredSubmodule ("Binaries", False)')
s = s.replace('os.path.join(os.environ.get("UNIXNU_ROOT", os.path.join(WorkspaceRoot, "..", "UniXNU")), "package"),', '')
open(p, 'w').write(s)
PY

echo "== 5. python build environment =="
python3 -m venv "$ROOT/venv"
"$ROOT/venv/bin/pip" -q install --upgrade pip
"$ROOT/venv/bin/pip" -q install -r "$MU/pip-requirements.txt"
# shellcheck disable=SC1091
source "$ROOT/venv/bin/activate"

echo "== 6. external dependencies (Mu-Basetools, OneCrypto, nasm) =="
python3 -m edk2toolext.invocables.edk2_update -c "$MU/Platforms/Xiaomi/ishtarPkg/DeviceBuild.py"

echo "== 7. build =="
cd "$MU"
python3 build_uefi.py -d ishtar -r RELEASE

FD=$(find "$MU/Build" -path '*ishtarPkg*' -name 'SILICIUM_UEFI.fd' | head -1)
[ -n "$FD" ] || { echo "build.sh: no SILICIUM_UEFI.fd produced"; exit 1; }
echo "== done: $FD ($(stat -c %s "$FD") bytes, expected 0x300000) =="
cp "$FD" "$ROOT/SILICIUM_UEFI-ishtar.fd"
