#!/bin/bash
# 在 macOS runner 上构建 ishtar/H′ 内核（方案 B）。
#
# 为什么换到这里：HakiOS 的构建本来就有两条路——Linux 用 theos 的 cctools，
# macOS 用 Xcode 自带的 clang/cctools/mig。Linux 那条我们在导出头文件（EXPORT_HDRS）
# 上撞了十几轮：上游按 per-frame 的 unifdef flag 集分别剥私有块，我们的环境里
# 那套变量是空的，全局一刀切又会剥掉内核自己要的宏。macOS 上这些工具链行为是
# 上游作者日常验证的那一套，不再需要任何补丁去"修" unifdef。
#
#   ./build-xnu-macos.sh [arm64|arm64e]
set -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work-macos}
ARCH_STR=${1:-${XNU_ARCH:-arm64}}
XNU_TAG=xnu-12377.121.6
mkdir -p "$WORK"
log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

export RC_DARWIN_KERNEL_VERSION=${RC_DARWIN_KERNEL_VERSION:-12377.121.6}
export XNU_HOST_DARWIN=1        # xnu-env.sh / setup.sh 据此走 Xcode 路径

# ---------------------------------------------------------------- 1. iPhoneOS SDK
if [ ! -d "$WORK/theos/sdks/iPhoneOS16.5.sdk/usr/include" ]; then
    log "下载 theos SDK"
    curl -fsSL --retry 3 -o "$WORK/theos-sdks.tar.gz" \
        https://codeload.github.com/theos/sdks/tar.gz/refs/heads/master
    mkdir -p "$WORK/theos/sdks"
    tar -xzf "$WORK/theos-sdks.tar.gz" -C "$WORK/theos/sdks" 2>/dev/null || true
    D=$(find "$WORK/theos/sdks" -maxdepth 3 -type d -name 'iPhoneOS16.5.sdk' | head -1)
    [ -n "$D" ] && [ "$D" != "$WORK/theos/sdks/iPhoneOS16.5.sdk" ] && mv "$D" "$WORK/theos/sdks/"
fi
[ -d "$WORK/theos/sdks/iPhoneOS16.5.sdk/usr/include" ] || { log "没有 iPhoneOS16.5.sdk"; exit 1; }
export THEOS="$WORK/theos"

# ---------------------------------------------------------------- 2. XNU + H′
XNU_ROOT="$HERE/xnu-src/$XNU_TAG"
if [ ! -d "$XNU_ROOT" ]; then
    log "克隆 xnu @ $XNU_TAG 并打 dada 补丁"
    git clone -q --depth 1 --branch "$XNU_TAG" https://github.com/apple-oss-distributions/xnu.git "$XNU_ROOT" \
        || exit 1
    git -C "$XNU_ROOT" apply --whitespace=nowarn "$HERE/xnu-12377.121.6-dada.patch" || exit 1
fi
export XNU_SRC="$XNU_ROOT"
export DARWIN_REDWOOD="$HERE"

chmod +x "$HERE/xnu-build.sh" "$HERE/xnu-env.sh" 2>/dev/null
find "$HERE/xnu-deps" -name '*.sh' -exec chmod +x {} + 2>/dev/null
[ -d "$HERE/xnu-deps/host/bin" ] && find "$HERE/xnu-deps/host/bin" -type f -exec chmod +x {} + 2>/dev/null

# ---------------------------------------------------------------- 2b. unifdef（macOS 没有）
# 参考实现的 macOS 分支是 `link /usr/bin/unifdef host/bin/unifdef`，但 macOS 自 10.15
# 起就不带这个命令。缺了它，MakeInc.cmd 的 $(shell $(XCRUN) -find unifdef) 得到空值，
# 导出头文件就成了原样拷贝，随后报 lock_rw.h 私有类型未定义。
if [ ! -x "$HERE/xnu-deps/host/bin/unifdef" ] || ! "$HERE/xnu-deps/host/bin/unifdef" -h >/dev/null 2>&1; then
    log "编译 unifdef（macOS 未自带）"
    mkdir -p "$WORK/unifdef" "$HERE/xnu-deps/host/bin"
    curl -fsSL --retry 3 -o "$WORK/unifdef.tar.gz" \
        https://codeload.github.com/fanf2/unifdef/tar.gz/refs/heads/master
    tar -xzf "$WORK/unifdef.tar.gz" -C "$WORK/unifdef" --strip-components=1
    printf '"@(#) $Version: 2.12 $\\n"\n' > "$WORK/unifdef/version.h"
    ( cd "$WORK/unifdef" && cc -std=gnu11 -O2 -w -o "$HERE/xnu-deps/host/bin/unifdef" unifdef.c ) \
        || { log "unifdef 编译失败"; exit 1; }
    chmod +x "$HERE/xnu-deps/host/bin/unifdef"
fi
log "unifdef: $("$HERE/xnu-deps/host/bin/unifdef" -h 2>&1 | head -1)"

# ---------------------------------------------------------------- 3. 依赖
log "setup.sh --stage1（macOS：cctools/mig 来自 Xcode）"
( cd "$HERE" && bash xnu-deps/setup.sh --stage1 ) >"$WORK/setup.log" 2>&1 \
    || { log "stage1 失败"; tail -40 "$WORK/setup.log"; exit 1; }

log "setup.sh --stage2（导出头 + 静态库）"
( cd "$HERE" && bash xnu-deps/setup.sh --stage2 ) >>"$WORK/setup.log" 2>&1 \
    || { log "stage2 失败（继续，看内核能否编）"; tail -20 "$WORK/setup.log"; }

# ---------------------------------------------------------------- 4. 编内核
log "xnu-build.sh（MACHINE=BCM2837 XNU_ARCH=$ARCH_STR，macOS 宿主）"
( cd "$HERE" && source xnu-env.sh && XNU_ARCH="$ARCH_STR" MACHINE=BCM2837 \
    bash xnu-build.sh -j"$(sysctl -n hw.ncpu)" -k ) >"$WORK/xnubuild.log" 2>&1
log "构建退出码 $?"

KER=$(find "$XNU_ROOT/BUILD/obj" -maxdepth 3 -type f -name 'mach.*' 2>/dev/null | grep -vE '\.(o|d|a)$' | head -3)
[ -n "$KER" ] && ls -l $KER 2>/dev/null | head -3
if [ -n "$KER" ]; then
    cp "$(echo "$KER" | head -1)" "$HERE/mach.ishtar"
    log "内核：$HERE/mach.ishtar（$(stat -f %z "$HERE/mach.ishtar") 字节）"
    exit 0
fi
log "没有产出内核，xnubuild.log 末尾："
tail -60 "$WORK/xnubuild.log"
exit 1
