#!/bin/bash
# 在 CI 里构建 ishtar/H′ 内核：Apple XNU 12377.121.6 + HakiOS 设备层。
#
# HakiOS 的构建需要 Apple 的 cctools（ld64、nm、otool、strip…）和一份 iPhoneOS SDK。
# macOS 上两者来自 Xcode；Linux 上上游做法是 theos，但 theos 的 Linux 工具链
# 只有 x86_64 版。所以这里自己编 cctools-port，并拼出一个恰好满足
# xnu-deps/setup.sh 的 $THEOS 布局。
#
#   ./build-xnu.sh [arm64|arm64e]
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
NPROC=$(nproc)
ARCH_STR=${1:-${XNU_ARCH:-arm64}}
XNU_TAG=xnu-12377.121.6

mkdir -p "$WORK"
log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

# ---------------------------------------------------------------- 1. Apple cctools (host build)
if [ ! -x "$WORK/cctools/bin/ld" ]; then
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
log "cctools: $(ls "$WORK/cctools/bin" | tr '\n' ' ')"

# ---------------------------------------------------------------- 2. theos SDK
if [ ! -d "$WORK/sdks/iPhoneOS16.5.sdk/usr/include" ]; then
    log "下载 theos SDK（165 MB）"
    curl -fsSL --retry 3 -o "$WORK/theos-sdks.tar.gz" \
        https://codeload.github.com/theos/sdks/tar.gz/refs/heads/master
    mkdir -p "$WORK/sdks" && tar -xzf "$WORK/theos-sdks.tar.gz" -C "$WORK/sdks" \
        --wildcards '*/iPhoneOS16.5.sdk/*' --strip-components=1 2>/dev/null || true
    # the tarball has sdks-<branch>/iPhoneOS16.5.sdk; normalise either layout
    if [ ! -d "$WORK/sdks/iPhoneOS16.5.sdk" ]; then
        D=$(find "$WORK/sdks" -maxdepth 3 -type d -name 'iPhoneOS16.5.sdk' | head -1)
        [ -n "$D" ] && mv "$D" "$WORK/sdks/"
    fi
fi
[ -d "$WORK/sdks/iPhoneOS16.5.sdk/usr/include" ] || { log "没有 iPhoneOS16.5.sdk"; ls "$WORK/sdks" | head; exit 1; }

# ---------------------------------------------------------------- 3. the $THEOS layout setup.sh expects
mkdir -p "$WORK/theos/toolchain/linux/iphone/bin" "$WORK/theos/sdks"
# cctools-port installs the tools under the target triple (aarch64-apple-darwin-ld, ...),
# while xnu-deps/setup.sh looks for the theos layout with plain names (ld, nm, otool, ...).
for tool in ld nm otool strip lipo libtool nmedit ctf_insert codesign_allocate \
            install_name_tool ar ranlib as size strings ObjectDump; do
    [ -e "$WORK/cctools/bin/aarch64-apple-darwin-$tool" ] && \
        ln -sfn "$WORK/cctools/bin/aarch64-apple-darwin-$tool" "$WORK/theos/toolchain/linux/iphone/bin/$tool"
done
ln -sfn "$WORK/theos/toolchain/linux/iphone/bin" "$WORK/theos/toolchain/linux/iphone/bin-link"
ls "$WORK/theos/toolchain/linux/iphone/bin" | tr '\n' ' '; echo
ln -sfn "$WORK/sdks/iPhoneOS16.5.sdk" "$WORK/theos/sdks/iPhoneOS16.5.sdk"
export THEOS="$WORK/theos"

# ---------------------------------------------------------------- 4. XNU + the H′ patch
XNU_ROOT="$HERE/xnu-src/$XNU_TAG"
if [ ! -d "$XNU_ROOT" ]; then
    log "克隆 apple-oss-distributions/xnu @ $XNU_TAG"
    git clone -q --depth 1 --branch "$XNU_TAG" https://github.com/apple-oss-distributions/xnu.git "$XNU_ROOT" \
        || { log "克隆失败"; exit 1; }
    git -C "$XNU_ROOT" apply --whitespace=nowarn "$HERE/xnu-12377.121.6-dada.patch" \
        || { log "dada 补丁打不上"; exit 1; }
fi
export XNU_SRC="$XNU_ROOT"
export DARWIN_REDWOOD="$HERE"

# ---------------------------------------------------------------- 5. dependencies, then the kernel
# 内核版本号：MakeInc.kernel:299 会去 SDK/KDK 的 System.kext/Info.plist 里读 CFBundleVersion，
# 我们的 SDK 是 theos 的公开 SDK，没有 System.kext，于是报
# "Could not determine xnu version from SDK or KDK"。MakeInc.kernel 自己给了逃生口：
export RC_DARWIN_KERNEL_VERSION=${RC_DARWIN_KERNEL_VERSION:-12377.121.6}
log "RC_DARWIN_KERNEL_VERSION=$RC_DARWIN_KERNEL_VERSION"

# 用 Git Data API 上传时丢了可执行位（mode 100644），这里补回来；
# 否则 setup.sh 里的 stage2 会以 "xnu-build.sh: Permission denied" 失败。
chmod +x "$HERE/xnu-build.sh" "$HERE/xnu-env.sh" 2>/dev/null
find "$HERE/xnu-deps" -name '*.sh' -exec chmod +x {} + 2>/dev/null
# host/bin 里是一批没有扩展名的脚本（xcrun / sw_vers / plutil / codesign / iig / install /
# xnu-clang）：Git API 上传同样丢了 +x，make 会报 "xcrun: Permission denied"。
[ -d "$HERE/xnu-deps/host/bin" ] && find "$HERE/xnu-deps/host/bin" -type f -exec chmod +x {} + 2>/dev/null

log "xnu-deps/setup.sh"
( cd "$HERE" && bash xnu-deps/setup.sh ) >"$WORK/setup.log" 2>&1 \
    || { log "setup.sh 失败，日志如下："; tail -40 "$WORK/setup.log"
         for extra in "$HERE/xnu-deps/exporthdrs.log" "$HERE/xnu-deps/stage2.log" \
                      "$HERE/xnu-deps/mig-build.log" "$HERE/xnu-deps/tcsh-build.log"; do
             [ -f "$extra" ] && { log "--- $(basename "$extra") ---"; tail -40 "$extra"; }
         done
         exit 1; }

log "xnu-build.sh (MACHINE=BCM2837 XNU_ARCH=$ARCH_STR)"
( cd "$HERE" && source xnu-env.sh && XNU_ARCH="$ARCH_STR" MACHINE=BCM2837 \
    bash xnu-build.sh -j"$NPROC" -k ) >"$WORK/xnubuild.log" 2>&1
rc=$?
KER=$(find "$XNU_ROOT/BUILD/obj" -maxdepth 3 -name 'mach.*.unstripped' -o -maxdepth 3 -name 'mach.*' -type f 2>/dev/null | head -5)
log "构建退出码 rc=$rc"
ls -l $KER 2>/dev/null | head
[ -n "$KER" ] && cp $(echo "$KER" | head -1) "$HERE/mach.ishtar" && log "内核：$HERE/mach.ishtar"
tail -25 "$WORK/xnubuild.log"
[ -n "$KER" ] || { log "没有产出内核"; exit 1; }
