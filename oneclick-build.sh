#!/usr/bin/env bash
# =============================================================================
# ishtar 一键编译（在 PC 上跑，产出可直接 fastboot boot 的镜像）
#
#   ./ishtar-oneclick.sh <GitHub token>          # 从私有仓库拉取全部输入
#   GH_TOKEN=xxx ./ishtar-oneclick.sh
#   ./ishtar-oneclick.sh --from ./ci-repo        # 已手动准备好仓库目录时
#
# 产出（都在 ./out/）：
#   SILICIUM_UEFI-ishtar.fd   UEFI 固件（必须正好 3,145,728 字节）
#   loader.efi                UEFI 下的 XNU loader（AArch64 PE）
#   usb-payload.bin           XNUP 载荷（loader.efi + --usb）
#   ishtar-boot.img           ⭐ 用 PC 执行：fastboot boot out/ishtar-boot.img
#   RESULT.txt                各项尺寸与 sha256（把这份和镜像一起传回来）
#
# 依赖（脚本会自己检查）：git curl tar xz python3 make clang lld nasm
#   Debian/Ubuntu: sudo apt install -y git curl xz-utils build-essential clang lld nasm python3 python3-venv uuid-dev acpica-tools
#   macOS:         brew install git curl xz llvm nasm python3
# =============================================================================
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/out"
WORK="$HERE/.work"
REPO_SLUG=${REPO_SLUG:-laggantulley-debug/ishtar-uefi-ci}
FD_EXPECT=3145728
mkdir -p "$OUT" "$WORK"

msg() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
die() { printf '\n\033[31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 参数与输入
SRC_REPO=""
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ "${1:-}" = "--from" ]; then
    SRC_REPO=$(cd "${2:?--from 需要一个目录}" && pwd)
elif [ -n "${1:-}" ]; then
    TOKEN="$1"
fi
[ "$(uname -s)" = Darwin ] && export XNU_HOST_DARWIN=1

msg "0. 检查依赖"
missing=""
for t in git curl tar xz python3 make; do command -v $t >/dev/null || missing="$missing $t"; done
# 编译器：clang 优先（XNU/UEFI 都需要），没有就退而求其次
command -v clang >/dev/null || command -v gcc >/dev/null || missing="$missing clang"
[ -n "$missing" ] && die "缺少命令：$missing
  Debian/Ubuntu: sudo apt install -y git curl xz-utils build-essential clang lld nasm python3 python3-venv uuid-dev acpica-tools
  macOS:         brew install git curl xz llvm nasm python3"
echo "  依赖齐备"

msg "1. 取得构建输入（板级包 / 厂商二进制 / 设备树 / 补丁）"
if [ -n "$SRC_REPO" ]; then
    SRC="$SRC_REPO"
    echo "  用本地目录：$SRC"
else
    [ -n "$TOKEN" ] || die "需要 GitHub token（私有仓库）；用法：./ishtar-oneclick.sh <token>"
    SRC="$WORK/repo"
    if [ -d "$SRC/.git" ]; then
        git -C "$SRC" fetch -q "https://${TOKEN}@github.com/${REPO_SLUG}.git" main || die "拉取仓库失败（token 或网络）"
        git -C "$SRC" reset -q --hard FETCH_HEAD
    else
        git clone -q "https://${TOKEN}@github.com/${REPO_SLUG}.git" "$SRC" || die "克隆仓库失败（token 或网络）"
    fi
    echo "  已取到：$(cd "$SRC" && git rev-parse --short HEAD)"
fi
for need in hakios/hakios.patch platform/ishtarPkg binaries/ishtar dtb/ishtar.dtb; do
    [ -e "$SRC/$need" ] || die "输入里缺少 $need（应在 ci 仓库中）"
done
echo "  板级包 / 厂商二进制 / 设备树 / hook 补丁 均在"

msg "2. 克隆 Mu-Silicium 并切到 HakiOS 的 BASE"
MU="$WORK/Mu-Silicium"
BASE=$(cat "$SRC/hakios/BASE")
if [ ! -d "$MU/.git" ]; then
    git clone -q https://github.com/Project-Silicium/Mu-Silicium.git "$MU" || die "克隆 Mu-Silicium 失败"
fi
git -C "$MU" fetch -q --depth 1 origin "$BASE" || die "取不到 BASE $BASE"
git -C "$MU" checkout -q "$BASE"
echo "  Mu-Silicium @ $(git -C "$MU" rev-parse --short HEAD)"

msg "3. 构建 UEFI 固件（这一步最久，约 10–20 分钟）"
if [ -f "$OUT/SILICIUM_UEFI-ishtar.fd" ] && [ "$(stat -c %s "$OUT/SILICIUM_UEFI-ishtar.fd" 2>/dev/null || stat -f %z "$OUT/SILICIUM_UEFI-ishtar.fd")" = "$FD_EXPECT" ]; then
    echo "  已存在合法固件，跳过（要重编请先删掉 $OUT/SILICIUM_UEFI-ishtar.fd）"
else
    MU="$MU" bash "$SRC/build.sh" >"$WORK/uefi-build.log" 2>&1 || {
        echo "  构建失败，日志末尾："; tail -30 "$WORK/uefi-build.log"; die "UEFI 构建失败（完整日志：$WORK/uefi-build.log）"; }
    FD=$(find "$MU/Build" -name 'SILICIUM_UEFI.fd' | head -1)
    [ -n "$FD" ] || die "构建成功但找不到 SILICIUM_UEFI.fd"
    cp "$FD" "$OUT/SILICIUM_UEFI-ishtar.fd"
    echo "  固件：$OUT/SILICIUM_UEFI-ishtar.fd"
fi

msg "4. 编 loader.efi（UEFI 下的 XNU loader）"
# 先看几个确定的位置（含软链），再退回全盘 find -L
LOADER_SRC=""
for cand in "$SRC/kernel/xnuloader/loader.c" "$SRC/xnuloader/loader.c" \
            "$WORK/hakios/xnuloader/loader.c" "$WORK/Mu-Silicium/xnuloader/loader.c"; do
    [ -f "$cand" ] && { LOADER_SRC="$cand"; break; }
done
[ -z "$LOADER_SRC" ] && LOADER_SRC=$(find -L "$WORK" "$SRC" -maxdepth 5 -name loader.c 2>/dev/null | head -1)
if [ -z "$LOADER_SRC" ]; then
    # loader 源码在 HakiOS 的内核仓库里；只为这一个目录克隆，下载量很小
    git clone -q --depth 1 --filter=blob:none --sparse https://github.com/oosexgang/hakios-xnu-kernel.git "$WORK/hakios" 2>/dev/null &&
        git -C "$WORK/hakios" sparse-checkout set xnuloader 2>/dev/null || true
    LOADER_SRC=$(find -L "$WORK/hakios" -name loader.c 2>/dev/null | head -1)
fi
[ -n "$LOADER_SRC" ] || die "找不到 xnuloader/loader.c（可从 HakiOS 仓库或本机 refs/dada/base/xnuloader 拷来，用 --from 指定目录）"
LDIR=$(dirname "$LOADER_SRC")
( cd "$LDIR" && ${CC:-clang} --target=aarch64-unknown-windows -ffreestanding -fno-builtin \
    -fno-stack-protector -fshort-wchar -mgeneral-regs-only -O1 -Wall -Wextra \
    -Wno-unused-parameter -c loader.c -o loader.obj ) || die "loader.c 编译失败"
LLD=$(command -v lld-link || command -v lld-link-19 || true)
[ -n "$LLD" ] || die "找不到 lld-link（Debian: apt install lld；macOS: brew install llvm，用 \$(brew --prefix llvm)/bin/lld-link）"
( cd "$LDIR" && "$LLD" /subsystem:efi_application /entry:efi_main /nodefaultlib \
    /base:0xA1000000 /out:loader.efi loader.obj ) || die "loader 链接失败"
cp "$LDIR/loader.efi" "$OUT/loader.efi"
echo "  loader.efi：$(stat -c %s "$OUT/loader.efi" 2>/dev/null || stat -f %z "$OUT/loader.efi") 字节"

msg "5. 打 XNUP 载荷（loader.efi + --usb）"
# mkpayload.py 与 loader.c 同目录（xnuloader/），优先直接用
MKPAYLOAD="$SRC/kernel/mkpayload.py"
[ -f "$MKPAYLOAD" ] || MKPAYLOAD="$(dirname "$LOADER_SRC")/mkpayload.py"
[ -f "$MKPAYLOAD" ] || MKPAYLOAD=$(find -L "$SRC" "$WORK" -name mkpayload.py 2>/dev/null | head -1)
[ -n "$MKPAYLOAD" ] && [ -f "$MKPAYLOAD" ] || die "找不到 mkpayload.py"
python3 "$MKPAYLOAD" -o "$OUT/usb-payload.bin" "loader.efi=$OUT/loader.efi" --usb || die "mkpayload 失败"
echo "  usb-payload.bin：$(stat -c %s "$OUT/usb-payload.bin" 2>/dev/null || stat -f %z "$OUT/usb-payload.bin") 字节"

msg "6. 打 boot 镜像（BootShim + 固件 + 载荷 + 设备树）"
MKXNUIMG="$SRC/mkxnuimg.py"
[ -f "$MKXNUIMG" ] || MKXNUIMG=$(find -L "$SRC" "$WORK" -maxdepth 4 -name mkxnuimg.py 2>/dev/null | head -1)
if [ -z "$MKXNUIMG" ] || [ ! -f "$MKXNUIMG" ]; then
    die "输入里缺少 mkxnuimg.py（应在 ci 仓库根目录）"
fi
# BootShim：Mu-Silicium 自带，用 FD_BASE/PAYLOAD_BASE 编译
( cd "$MU/BootShim" && rm -f BootShim.bin BootShim.elf &&
  make REQUIRES_KERNEL_HEADER=1 FD_BASE=0xa7100000 FD_SIZE=0x300000 \
       CFLAGS='--target=aarch64-linux-gnu -DPAYLOAD_BASE=0xa8000000' >/dev/null 2>&1 ) ||
  die "BootShim 编译失败（需要 aarch64 交叉目标；Linux 用 clang，macOS 用 llvm）"
# mkxnuimg 期望 Mu-Silicium 在它旁边
BDIR="$WORK/bootimg"; rm -rf "$BDIR"; mkdir -p "$BDIR"
ln -sfn "$MU" "$BDIR/Mu-Silicium"
cp "$MKXNUIMG" "$BDIR/"; [ -d "$(dirname "$MKPAYLOAD")" ] && ln -sfn "$(dirname "$MKPAYLOAD")" "$BDIR/xnuloader"
( cd "$BDIR" && UEFI_FD="$OUT/SILICIUM_UEFI-ishtar.fd" DTB="$SRC/dtb/ishtar.dtb" \
    XNU_HOST_DARWIN="${XNU_HOST_DARWIN:-}" \
    FD_BASE=0xa7100000 FD_SIZE=0x300000 PAYLOAD_BASE=0xa8000000 UEFI_TARGET=ishtar HEADER_VERSION=0 \
    python3 mkxnuimg.py -p "$OUT/usb-payload.bin" -o "$OUT/ishtar-boot.img" ) || die "mkxnuimg 失败"

msg "7. 校验并写 RESULT.txt"
python3 - "$OUT" "$FD_EXPECT" <<'PY' | tee "$OUT/RESULT.txt"
import hashlib, os, struct, sys, zlib
out, expect = sys.argv[1], int(sys.argv[2])
def line(name, path, want=None):
    if not os.path.exists(path):
        print(f'{name:<24} 缺失'); return
    size = os.path.getsize(path)
    h = hashlib.sha256(open(path,'rb').read()).hexdigest()
    ok = '' if want is None else ('  ✓ 尺寸正确' if size == want else f'  ✗ 应为 {want}')
    print(f'{name:<24} {size:>9} B  sha256 {h}{ok}')
fd = os.path.join(out, 'SILICIUM_UEFI-ishtar.fd')
line('固件 .fd', fd, expect)
line('loader.efi', os.path.join(out, 'loader.efi'))
line('usb-payload.bin', os.path.join(out, 'usb-payload.bin'))
img = os.path.join(out, 'ishtar-boot.img')
line('ishtar-boot.img', img)
if os.path.exists(img):
    d = open(img,'rb').read()
    ksize = struct.unpack_from('<I', d, 0x08)[0]
    page = struct.unpack_from('<I', d, 0x24)[0]
    hver = struct.unpack_from('<I', d, 0x28)[0]
    z = zlib.decompressobj(31); blob = z.decompress(d[page:page+ksize]) + z.flush()
    print()
    print(f'boot 镜像头部              {d[:8].decode("ascii","replace")}  header_version={hver}  page={page}')
    print(f'解压后                     {len(blob)} B  (_FVH @ {blob.find(b"_FVH")}, XNUP @ {blob.find(b"XNUP")})')
    print(f'设备树                     {len(z.unused_data)} B  头 {z.unused_data[:4].hex()}')
    ok = (d[:8] == b'ANDROID!' and blob.find(b'_FVH') > 0 and blob.find(b'XNUP') > 0 and len(z.unused_data) > 0)
    print(f'结构校验                   {"通过" if ok else "不通过"}')
PY

cat <<EOF

===============================================================================
完成。产物在：$OUT
===============================================================================
下一步（用 PC 对手机执行，只在内存运行，不写任何分区）：

    fastboot boot $OUT/ishtar-boot.img

请把这两样传回来：
    1. $OUT/RESULT.txt        （尺寸与哈希，用来核对）
    2. 屏幕拍到的内容 / loader 打印的日志（如果能连 USB：xl log）

重启即回原系统；本项目不刷写任何分区。
EOF
