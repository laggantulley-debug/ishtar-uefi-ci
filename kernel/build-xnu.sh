#!/bin/bash
# 在 CI 里构建 ishtar/H′ 内核：Apple XNU 12377.121.6 + HakiOS 设备层（dada 叠加层）。
set -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
NPROC=$(nproc)
ARCH_STR=${1:-${XNU_ARCH:-arm64}}
XNU_TAG=xnu-12377.121.6
mkdir -p "$WORK"
log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

export RC_DARWIN_KERNEL_VERSION=${RC_DARWIN_KERNEL_VERSION:-12377.121.6}

if [ ! -x "$WORK/cctools/bin/aarch64-apple-darwin-ld" ]; then
    log "下载 cctools-port"
    curl -fsSL --retry 3 -o "$WORK/cctools-port.tar.gz" \
        https://codeload.github.com/tpoechtrager/cctools-port/tar.gz/refs/heads/master
    tar -xzf "$WORK/cctools-port.tar.gz" -C "$WORK"
    SRC=$(find "$WORK" -maxdepth 1 -type d -name 'cctools-port-*' | head -1)/cctools
    log "编译 cctools + ld64（目标 aarch64-apple-darwin）"
    ( cd "$SRC" && ./configure --prefix="$WORK/cctools" --target=aarch64-apple-darwin >configure.log 2>&1 \
        && make -j"$NPROC" >make.log 2>&1 && make install >>make.log 2>&1 ) \
        || { log "cctools 构建失败"; tail -40 "$SRC/make.log" 2>/dev/null; exit 1; }
fi
log "cctools 就绪"

if [ ! -d "$WORK/sdks/iPhoneOS16.5.sdk/usr/include" ]; then
    log "下载 theos SDK（165 MB）"
    curl -fsSL --retry 3 -o "$WORK/theos-sdks.tar.gz" \
        https://codeload.github.com/theos/sdks/tar.gz/refs/heads/master
    mkdir -p "$WORK/sdks" && tar -xzf "$WORK/theos-sdks.tar.gz" -C "$WORK/sdks" 2>/dev/null || true
    D=$(find "$WORK/sdks" -maxdepth 3 -type d -name 'iPhoneOS16.5.sdk' | head -1)
    if [ -n "$D" ] && [ "$D" != "$WORK/sdks/iPhoneOS16.5.sdk" ]; then mv "$D" "$WORK/sdks/"; fi
fi
[ -d "$WORK/sdks/iPhoneOS16.5.sdk/usr/include" ] \
    || { log "没有 iPhoneOS16.5.sdk"; ls "$WORK/sdks" 2>/dev/null | head; exit 1; }

mkdir -p "$WORK/theos/toolchain/linux/iphone/bin" "$WORK/theos/sdks"
for tool in ld nm otool strip lipo libtool nmedit ctf_insert codesign_allocate \
            install_name_tool ar ranlib as size strings; do
    [ -e "$WORK/cctools/bin/aarch64-apple-darwin-$tool" ] && \
        ln -sfn "$WORK/cctools/bin/aarch64-apple-darwin-$tool" "$WORK/theos/toolchain/linux/iphone/bin/$tool"
done
ln -sfn "$WORK/sdks/iPhoneOS16.5.sdk" "$WORK/theos/sdks/iPhoneOS16.5.sdk"
export THEOS="$WORK/theos"
log "THEOS=$THEOS"

XNU_ROOT="$HERE/xnu-src/$XNU_TAG"
if [ ! -d "$XNU_ROOT" ]; then
    log "克隆 apple-oss-distributions/xnu @ $XNU_TAG"
    git clone -q --depth 1 --branch "$XNU_TAG" https://github.com/apple-oss-distributions/xnu.git "$XNU_ROOT" \
        || { log "克隆失败"; exit 1; }
    git -C "$XNU_ROOT" apply --whitespace=nowarn "$HERE/xnu-12377.121.6-dada.patch" \
        || { log "dada 补丁打不上"; exit 1; }
fi

# ---------------------------------------------------------------- 4b. 不再改写导出头规则
# 2026-11-03 之前，这里有一整套「修导出头」的动作：往 makedefs/MakeInc.rule 的 INSTALLHDRS
# 模板里写字面量 -U… 剥离参数、把 unifdef 换成"每次调用都追加 -U"的包装器、给 SDK 打
# TargetConditionals.h 桩、以及把 EXPORT_HDRS 里 1120 个头全量剥两遍。这些全部删除。
#
# 根因（已用 clang 在本机复现，见 KERNEL-BUILD-STATUS.md）：
#   xnu-deps/setup.sh 编 libfirehose_kernel.a 时传了 -DXNU_KERNEL_PRIVATE=0。
#   XNU 的锁头里 #if 与 #ifdef 混用：值 0 让 `#ifdef XNU_KERNEL_PRIVATE` 成立、
#   却让 `#if XNU_KERNEL_PRIVATE` 不成立 —— 于是 lck_rw_other_t / __lck_rw_other_extern
#   的 typedef 与宏被跳过，23 条用到它们的声明留下 → unknown type name。
#   改成 -UXNU_KERNEL_PRIVATE（不定义）后 #if 与 #ifdef 一致，整段同生同死。
#
# 为什么不能再剥导出头：
#   BUILD/obj/EXPORT_HDRS 本来就是 INSTALL 直拷（MakeInc.rule:478/491），上游从不剥它；
#   剥掉 `#ifdef XNU_KERNEL_PRIVATE` 会把 osfmk/kern/debug.h 的 #else 分支
#   （`#include <TargetConditionals.h>`）剥成活的，内核编译直接 1383 条 fatal error。
#   内核编译自己带着 -DXNU_KERNEL_PRIVATE -DMACH_KERNEL_PRIVATE（MakeInc.def:158 + 组件
#   Makefile:22），原样的头是正确的。
#
# UNIFDEF 指到绝对路径这一条保留：MakeInc.cmd:261 用 $(shell $(XCRUN) -find unifdef) 求值，
# 让工具必须先被找到；这只影响 System.framework 那套框架头（内核不读），与内核无关。

python3 - "$XNU_ROOT" <<'PATCH'
import sys, os
root = sys.argv[1]
p = os.path.join(root, 'makedefs/MakeInc.cmd')
s = open(p).read()
old = "\texport UNIFDEF := $(shell $(XCRUN) -sdk $(SDKROOT) -find unifdef)"
new = "\texport UNIFDEF := /usr/local/bin/unifdef"
if old in s:
    s = s.replace(old, new, 1)
    open(p, 'w').write(s)
    print('MakeInc.cmd: UNIFDEF 固定为 /usr/local/bin/unifdef')
else:
    print('MakeInc.cmd: 已打过或锚点不匹配')
PATCH

export XNU_SRC="$XNU_ROOT"
export DARWIN_REDWOOD="$HERE"

# 设备层需要、但 dada 补丁没带的文件（目前只有触控固件头 redwood_focaltech_fw.h，706 KB）。
# 按相对路径补进源码树；已存在就不动，免得覆盖补丁里的版本。
if [ -d "$HERE/xnu-extras" ]; then
    ( cd "$HERE/xnu-extras" && find . -type f -print0 | while IFS= read -r -d '' f; do
        t="$XNU_ROOT/${f#./}"
        [ -f "$t" ] && continue
        mkdir -p "$(dirname "$t")" && cp "$f" "$t" && \
            log "补进源码树：${f#./}（$(stat -c %s "$f") 字节）"
    done )
fi

chmod +x "$HERE/xnu-build.sh" "$HERE/xnu-env.sh" 2>/dev/null
find "$HERE/xnu-deps" -name '*.sh' -exec chmod +x {} + 2>/dev/null
[ -d "$HERE/xnu-deps/host/bin" ] && find "$HERE/xnu-deps/host/bin" -type f -exec chmod +x {} + 2>/dev/null

log "setup.sh --stage1"
( cd "$HERE" && bash xnu-deps/setup.sh --stage1 ) >"$WORK/setup.log" 2>&1 \
    || { log "stage1 失败"; tail -40 "$WORK/setup.log"; exit 1; }

if [ -d "$HERE/xnu-deps/host/bin" ]; then
    for t in "$HERE"/xnu-deps/host/bin/*; do
        [ -f "$t" ] && { sudo install -m755 "$t" /usr/local/bin/ 2>/dev/null || cp -f "$t" /usr/local/bin/ 2>/dev/null || true; }
    done
    log "宿主工具已装到 /usr/local/bin：$(ls /usr/local/bin 2>/dev/null | grep -cE 'unifdef|xcrun|sw_vers|plutil|codesign|iig|tcsh') 个"
fi

log "setup.sh --stage2（导出头文件 + 静态库）"
( cd "$HERE" && bash xnu-deps/setup.sh --stage2 ) >>"$WORK/setup.log" 2>&1
STAGE2_RC=$?
if [ "$STAGE2_RC" != 0 ]; then
    log "警告：stage2 退出码 $STAGE2_RC —— 仍继续做闸门检查"
    grep -nE 'error:|fatal error' "$WORK/setup.log" | head -10
else
    log "stage2 完成"
fi

# ---------------------------------------------------------------- 10 秒头部闸门
# 历史上每个卡点都停在"导出头 / 宏值"这一层，而每次发现要花掉 4~15 分钟编译。
# 这里在编译前用几十毫秒把三件事钉死，任何一条不成立就直接退出。
EXPORT_DIR="$XNU_ROOT/BUILD/obj/EXPORT_HDRS"
gate_fail=0
ok()  { printf '  [闸门 ✓] %s\n' "$*"; }
bad() { printf '  [闸门 ✗] %s\n' "$*"; gate_fail=1; }

# 1) 不允许任何「定义成 0」的 kernel-private 宏：值 0 会让 #if 与 #ifdef 打架
if grep -rnE -- '-DXNU_KERNEL_PRIVATE=0' "$HERE/xnu-deps" >"$WORK/gate-macro0.txt" 2>&1; then
    bad "xnu-deps 里还有 -DXNU_KERNEL_PRIVATE=0："
    cat "$WORK/gate-macro0.txt"
else
    ok "没有 -DXNU_KERNEL_PRIVATE=0（用的是 -UXNU_KERNEL_PRIVATE）"
fi

# 2) 导出头必须是源码的原样拷贝（EXPORT_HDRS 走 INSTALL 直拷，上游不剥）
for f in osfmk/kern/debug.h osfmk/kern/lock_rw.h; do
    if [ ! -f "$EXPORT_DIR/$f" ]; then
        bad "缺 $EXPORT_DIR/$f（stage2 没导出成功？见 work/setup.log）"
    elif cmp -s "$EXPORT_DIR/$f" "$XNU_ROOT/$f"; then
        ok "导出头未被改写：$f（$(wc -l < "$EXPORT_DIR/$f") 行）"
    else
        bad "$f 与源码不一致（导出 $(wc -l < "$EXPORT_DIR/$f") 行 vs 源码 $(wc -l < "$XNU_ROOT/$f") 行）——被剥离/改写过"
    fi
done

# 3) 用两组定义集预处理 lock_rw.h：宏和用到它的声明必须同生同死
if [ -f "$EXPORT_DIR/osfmk/kern/lock_rw.h" ]; then
    PROBE="$WORK/gate-lock_rw.h"
    grep -v '^#include' "$EXPORT_DIR/osfmk/kern/lock_rw.h" > "$PROBE"
    KERNEL_DEFS="-DXNU_KERNEL_PRIVATE -DMACH_KERNEL_PRIVATE -DKERNEL=1 -DKERNEL_PRIVATE=1 -DPRIVATE=1"
    CLIENT_DEFS="-UXNU_KERNEL_PRIVATE -DKERNEL=1 -DKERNEL_PRIVATE=1 -DPRIVATE=1"
    K_N=$(clang -E -P -nostdinc $KERNEL_DEFS -x c "$PROBE" 2>/dev/null | grep -c 'lck_rw_other_t')
    C_N=$(clang -E -P -nostdinc $CLIENT_DEFS -x c "$PROBE" 2>/dev/null | grep -c 'lck_rw_other_t')
    ok "lock_rw.h 预处理：内核定义集 $K_N 行、公开定义集 $C_N 行（期望 内核>0、公开=0）"
    [ "$K_N" -gt 0 ] || bad "内核定义集下 lck_rw_other_t 一行都没有——宏被剥了"
    [ "$C_N" -eq 0 ] || bad "公开定义集下还有 $C_N 行 lck_rw_other_t——又踩回 #if/#ifdef 打架"
fi

if [ "$gate_fail" != 0 ]; then
    log "闸门未通过，不进入内核编译（省掉一轮 4 分钟）"
    exit 1
fi
log "闸门通过，开始编译"

log "xnu-build.sh（MACHINE=BCM2837 XNU_ARCH=$ARCH_STR，单轮）"
( cd "$HERE" && source xnu-env.sh && XNU_ARCH="$ARCH_STR" MACHINE=BCM2837 \
# ---------------------------------------------------------------- 补 TargetConditionals.h
# 实测：放进两个 SDK 的 usr/include 后 clang 仍找不到（构建的 include 根是
# BUILD/obj/EXPORT_HDRS，不是 SDK）。所以直接放进 EXPORT_HDRS 根目录。
TC_SRC="$HERE/xnu-deps/build/pthread/inc/TargetConditionals.h"
if [ -f "$TC_SRC" ] && [ -d "$EXPORT_DIR" ]; then
    cp -f "$TC_SRC" "$EXPORT_DIR/TargetConditionals.h" 2>/dev/null && \
        log "补 TargetConditionals.h -> $EXPORT_DIR/"
fi

    bash xnu-build.sh -j"$NPROC" -k ) >"$WORK/xnubuild.log" 2>&1
rc=$?
log "构建退出码 $rc"
KER=$(find "$XNU_ROOT/BUILD/obj" -maxdepth 3 -type f -name 'mach.*' 2>/dev/null | grep -vE '\.(o|d|a)$' | head -3)

[ -n "$KER" ] && ls -l $KER 2>/dev/null | head -3
if [ -n "$KER" ]; then
    cp "$(echo "$KER" | head -1)" "$HERE/mach.ishtar"
    cp "$(echo "$KER" | head -1)" "$HERE/../mach.ishtar"   # workflow 的 artifact 路径在仓库根
    log "内核：$HERE/mach.ishtar（$(stat -c %s "$HERE/mach.ishtar") 字节）"
    exit 0
fi
HDR="$EXPORT_DIR/osfmk/kern/lock_rw.h"
[ -f "$HDR" ] && log "最终 lock_rw.h: $(wc -l < "$HDR") 行（源码 $(wc -l < "$XNU_ROOT/osfmk/kern/lock_rw.h") 行）"
log "没有产出内核，xnubuild.log 末尾："
tail -60 "$WORK/xnubuild.log"

# ---- 收集诊断材料（第一条报错就够下结论，不用再拖 3 MB 日志）------------
DBG="$WORK/debug"; mkdir -p "$DBG"
log "收集诊断材料到 $DBG"
# 1) 报错行 + 文件头部（文件头有 make 的起点，便于对齐阶段）
{ grep -nE 'error:|fatal error|Error 1' "$WORK/xnubuild.log" 2>/dev/null | head -40
  echo '--- xnubuild.log 前 120 行 ---'
  head -120 "$WORK/xnubuild.log" 2>/dev/null; } > "$DBG/first-errors.txt"
# 2) 生成后的 Makefile（能看见组件级 CFLAGS 里的 -DMACH_KERNEL_PRIVATE）
find "$XNU_ROOT/BUILD/obj" -maxdepth 3 -type d -name 'DEVELOPMENT' 2>/dev/null | head -5 | while read d; do
    [ -f "$d/Makefile" ] && cp "$d/Makefile" "$DBG/generated-$(basename "$(dirname "$d")")-Makefile" 2>/dev/null
done
# 3) 真正决定成败的两处标志
{ echo '=== xnu-deps/setup.sh 的 firehose 定义集 ==='
  grep -n 'XNU_KERNEL_PRIVATE' "$HERE/xnu-deps/setup.sh"
  echo '=== MakeInc.def 的内核 DEFINES ==='
  sed -n '155,165p' "$XNU_ROOT/makedefs/MakeInc.def"; } > "$DBG/flags.txt" 2>&1
# 4) 导出头样本
[ -f "$HDR" ] && { wc -l "$HDR" > "$DBG/exported-lock_rw-head.txt"; head -80 "$HDR" >> "$DBG/exported-lock_rw-head.txt"; }
# 5) 工具与版本
{ command -v unifdef; ls -l "$HERE/xnu-deps/host/bin" 2>/dev/null; clang --version 2>&1 | head -2; } > "$DBG/tools.txt" 2>&1
ls -l "$DBG"
exit 1
