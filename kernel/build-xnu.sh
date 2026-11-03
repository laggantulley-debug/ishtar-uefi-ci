#!/bin/bash
# Build the ishtar/H′ kernel in CI: Apple XNU 12377.121.6 + the HakiOS device layer.
#
# The HakiOS build wants Apple's cctools (ld64, nm, otool, strip...) and an iPhoneOS SDK.
# On macOS both come from Xcode; on Linux the upstream way is theos, whose Linux toolchain
# is x86_64 only. So this builds cctools-port for the host and lays out a $THEOS that has
# exactly what xnu-deps/setup.sh looks for.
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
    log "fetching cctools-port"
    curl -fsSL --retry 3 -o "$WORK/cctools-port.tar.gz" \
        https://codeload.github.com/tpoechtrager/cctools-port/tar.gz/refs/heads/master
    tar -xzf "$WORK/cctools-port.tar.gz" -C "$WORK"
    SRC=$(find "$WORK" -maxdepth 1 -type d -name 'cctools-port-*' | head -1)/cctools
    log "building cctools + ld64 for aarch64-apple-darwin"
    ( cd "$SRC" && ./configure --prefix="$WORK/cctools" --target=aarch64-apple-darwin >configure.log 2>&1 \
        && make -j"$NPROC" >make.log 2>&1 && make install >>make.log 2>&1 ) \
        || { log "cctools build FAILED"; tail -40 "$SRC/make.log" 2>/dev/null; exit 1; }
fi
log "cctools: $(ls "$WORK/cctools/bin" | tr '\n' ' ')"

# ---------------------------------------------------------------- 2. theos SDK
if [ ! -d "$WORK/sdks/iPhoneOS16.5.sdk/usr/include" ]; then
    log "fetching the theos SDKs (165 MB)"
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
[ -d "$WORK/sdks/iPhoneOS16.5.sdk/usr/include" ] || { log "no iPhoneOS16.5.sdk"; ls "$WORK/sdks" | head; exit 1; }

# ---------------------------------------------------------------- 3. the $THEOS layout setup.sh expects
mkdir -p "$WORK/theos/toolchain/linux/iphone" "$WORK/theos/sdks"
ln -sfn "$WORK/cctools/bin" "$WORK/theos/toolchain/linux/iphone/bin"
ln -sfn "$WORK/sdks/iPhoneOS16.5.sdk" "$WORK/theos/sdks/iPhoneOS16.5.sdk"
export THEOS="$WORK/theos"

# ---------------------------------------------------------------- 4. XNU + the H′ patch
XNU_ROOT="$HERE/xnu-src/$XNU_TAG"
if [ ! -d "$XNU_ROOT" ]; then
    log "cloning apple-oss-distributions/xnu @ $XNU_TAG"
    git clone -q --depth 1 --branch "$XNU_TAG" https://github.com/apple-oss-distributions/xnu.git "$XNU_ROOT" \
        || { log "clone failed"; exit 1; }
    git -C "$XNU_ROOT" apply --whitespace=nowarn "$HERE/xnu-12377.121.6-dada.patch" \
        || { log "dada patch did not apply"; exit 1; }
fi
export XNU_SRC="$XNU_ROOT"
export DARWIN_REDWOOD="$HERE"

# ---------------------------------------------------------------- 5. dependencies, then the kernel
log "xnu-deps/setup.sh"
( cd "$HERE" && bash xnu-deps/setup.sh ) >"$WORK/setup.log" 2>&1 \
    || { log "setup.sh failed"; tail -40 "$WORK/setup.log"; exit 1; }

log "xnu-build.sh (MACHINE=BCM2837 XNU_ARCH=$ARCH_STR)"
( cd "$HERE" && source xnu-env.sh && XNU_ARCH="$ARCH_STR" MACHINE=BCM2837 \
    bash xnu-build.sh -j"$NPROC" -k ) >"$WORK/xnubuild.log" 2>&1
rc=$?
KER=$(find "$XNU_ROOT/BUILD/obj" -maxdepth 3 -name 'mach.*.unstripped' -o -maxdepth 3 -name 'mach.*' -type f 2>/dev/null | head -5)
log "build rc=$rc"
ls -l $KER 2>/dev/null | head
[ -n "$KER" ] && cp $(echo "$KER" | head -1) "$HERE/mach.ishtar" && log "kernel: $HERE/mach.ishtar"
tail -25 "$WORK/xnubuild.log"
[ -n "$KER" ] || { log "no kernel produced"; exit 1; }
