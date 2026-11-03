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
# ---------------------------------------------------------------- 4b. 修 XNU 的导出头规则
# MakeInc.rule 的 INSTALLHDRS 模板用 $(UNIFDEF) $(4) 生成导出头；在本环境里 $(4)
# （SPINCFRAME_UNIFDEF 等）展开为空，空参 unifdef 等于原样拷贝，于是导出头保留了
# XNU_KERNEL_PRIVATE 私有块，内核代码 -I 过去就报未定义类型。
# 修法：把私有块剥离参数**字面量**写进模板（不依赖变量展开时机），并把 UNIFDEF 固定成绝对路径。
python3 - "$XNU_ROOT" <<'PATCH'
import sys, os
root = sys.argv[1]
FLAGS = ("-UMACH_KERNEL_PRIVATE -UBSD_KERNEL_PRIVATE -UIOKIT_KERNEL_PRIVATE "
         "-ULIBKERN_KERNEL_PRIVATE -ULIBSA_KERNEL_PRIVATE -UPEXPERT_KERNEL_PRIVATE "
         "-UXNU_KERNEL_PRIVATE -UEXCLAVEKIT -UEXCLAVECORE")

# 1) 模板里强制带剥离参数
p = os.path.join(root, 'makedefs/MakeInc.rule')
s = open(p).read()
old = "$$(_v)$$(UNIFDEF) $(4) $$< > ./$(3)/$$*.unifdef.$$$$$$$$;"
new = "$$(_v)$$(UNIFDEF) $(4) " + FLAGS + " $$< > ./$(3)/$$*.unifdef.$$$$$$$$;"
if old in s and FLAGS not in s:
    s = s.replace(old, new, 1)
    open(p, 'w').write(s)
    print('MakeInc.rule: INSTALLHDRS 模板已加剥离参数')
else:
    print('MakeInc.rule: 已打过或锚点不匹配')

# 2) UNIFDEF 固定为绝对路径，不再靠 $(shell $(XCRUN) ...) 求值
p = os.path.join(root, 'makedefs/MakeInc.cmd')
s = open(p).read()
old = "	export UNIFDEF := $(shell $(XCRUN) -sdk $(SDKROOT) -find unifdef)"
new = "	export UNIFDEF := /usr/local/bin/unifdef"
if old in s:
    s = s.replace(old, new, 1)
    open(p, 'w').write(s)
    print('MakeInc.cmd: UNIFDEF 固定为 /usr/local/bin/unifdef')
else:
    print('MakeInc.cmd: 已打过或锚点不匹配')
PATCH

export XNU_SRC="$XNU_ROOT"
export DARWIN_REDWOOD="$HERE"

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

# 让每一次 unifdef 调用都带上"剥私有块"的参数。
# 导出的头文件在构建过程中会被重新生成，我们事后剥一次不够；而上游 make 规则
# 传进来的参数在这套环境里是空的（unifdef 空参 = 原样输出），所以直接换成包装器：
# 无论调用方传什么，私有块一律剥掉。
if [ -x /usr/local/bin/unifdef ] && [ ! -x /usr/local/bin/unifdef.real ]; then
    mv /usr/local/bin/unifdef /usr/local/bin/unifdef.real
    cat > /usr/local/bin/unifdef <<'WRAP'
#!/bin/sh
exec /usr/local/bin/unifdef.real "$@" \
    -UMACH_KERNEL_PRIVATE -UBSD_KERNEL_PRIVATE -UIOKIT_KERNEL_PRIVATE \
    -ULIBKERN_KERNEL_PRIVATE -ULIBSA_KERNEL_PRIVATE -UPEXPERT_KERNEL_PRIVATE \
    -UXNU_KERNEL_PRIVATE -UEXCLAVEKIT -UEXCLAVECORE
WRAP
    chmod +x /usr/local/bin/unifdef
    log "unifdef 已换成带私有块剥离参数的包装器"
fi

log "setup.sh --stage2（导出头文件 + 静态库）"
( cd "$HERE" && bash xnu-deps/setup.sh --stage2 ) >>"$WORK/setup.log" 2>&1
STAGE2_RC=$?
if [ "$STAGE2_RC" != 0 ]; then
    log "警告：stage2 退出码 $STAGE2_RC —— 仍继续编内核本体"
    tail -15 "$WORK/setup.log"
    HDR="$XNU_ROOT/BUILD/obj/EXPORT_HDRS/osfmk/kern/lock_rw.h"
    [ -f "$HDR" ] && log "导出头文件: $(wc -l < "$HDR") 行，__lck_rw_other_extern $(grep -c __lck_rw_other_extern "$HDR") 次"
else
    log "stage2 完成"
fi

# 导出头文件自己剥一遍 XNU_KERNEL_PRIVATE 族。
# 上游 make 的 UNIFDEF 规则在这套环境里没生效（导出的是原样拷贝，1186 行），
# 而内核代码会 -I 到 EXPORT_HDRS，于是 lock_rw.h/upsi.h 的私有块以"未定义类型"炸出来。
# 参数取自 makedefs/MakeInc.def 的 XNU_PRIVATE_UNIFDEF（参考实现 xnu-deps/setup.sh 同源）。
STRIP_FLAGS="-UMACH_KERNEL_PRIVATE -UBSD_KERNEL_PRIVATE -UIOKIT_KERNEL_PRIVATE -ULIBKERN_KERNEL_PRIVATE -ULIBSA_KERNEL_PRIVATE -UPEXPERT_KERNEL_PRIVATE -UXNU_KERNEL_PRIVATE -UEXCLAVEKIT -UEXCLAVECORE"
EXPORT_DIR="$XNU_ROOT/BUILD/obj/EXPORT_HDRS"
if [ -d "$EXPORT_DIR" ] && command -v unifdef >/dev/null 2>&1; then
    n=0
    while IFS= read -r -d '' f; do
        unifdef $STRIP_FLAGS "$f" > "$f.strip" 2>/dev/null
        rc=$?
        if [ $rc -eq 0 ] || [ $rc -eq 1 ]; then mv "$f.strip" "$f"; n=$((n+1)); else rm -f "$f.strip"; fi
    done < <(find "$EXPORT_DIR" -name '*.h' -print0)
    log "已剥私有块的头文件：$n 个"
    HDR="$EXPORT_DIR/osfmk/kern/lock_rw.h"
    [ -f "$HDR" ] && log "核对 lock_rw.h: $(wc -l < "$HDR") 行，__lck_rw_other_extern $(grep -c __lck_rw_other_extern "$HDR") 次"
else
    log "跳过导出头处理（目录或 unifdef 缺失）"
fi

log "xnu-build.sh（MACHINE=BCM2837 XNU_ARCH=$ARCH_STR）"
( cd "$HERE" && source xnu-env.sh && XNU_ARCH="$ARCH_STR" MACHINE=BCM2837 \
    bash xnu-build.sh -j"$NPROC" -k ) >"$WORK/xnubuild.log" 2>&1
log "内核构建退出码 $?"

KER=$(find "$XNU_ROOT/BUILD/obj" -maxdepth 3 -type f -name 'mach.*' 2>/dev/null | grep -vE '\.(o|d|a)$' | head -3)
[ -n "$KER" ] && ls -l $KER 2>/dev/null | head -3
if [ -n "$KER" ]; then
    cp $(echo "$KER" | head -1) "$HERE/mach.ishtar"
    log "内核：$HERE/mach.ishtar（$(stat -c %s "$HERE/mach.ishtar") 字节）"
    exit 0
fi
log "没有产出内核，xnubuild.log 末尾："
tail -60 "$WORK/xnubuild.log"
exit 1
