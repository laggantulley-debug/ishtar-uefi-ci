# ishtar UEFI / 内核 — 云端构建仓库

这个仓库把 ishtar（小米 13 Ultra，SM8550-AB）的 **UEFI 固件**和 **HakiOS 内核**都放到 GitHub Actions 上构建，
本机（aarch64 + proot）只负责准备输入、取回产物并校验。

## 一、仓库内容

| 目录 | 内容 | 说明 |
|---|---|---|
| `hakios/` | HakiOS 的两项启动 hook：`BootShim.S` 里的 **XNUP 载荷拷贝**、`BootManagerLib` 里**改用 `XnuLoader.c` 启动内核** | 来自 `oosexgang/hakios-uefi`，`BASE` 指向 Mu-Silicium 的固定提交 |
| `platform/ishtarPkg/` | 板级包：内存图、配置表、GOP 日志、按键输入 | 已摘掉 R3/prelink 的 `UniXNUPkg`、`DarwinBootPkg`（两套 loader 不能共存） |
| `binaries/ishtar/` | 厂商 DXE 驱动 **97 个**，以及 **54 个 raw 文件**（`SecParti.cfg`、面板 XML、`BDS_Menu.cfg`…） | 全部从**本机自己的 `uefi.img`** 里抽出；公开 nuwa 集有 5 个模块不同（含 `DisplayDxe`），故不使用 |
| `resources/ishtar.toml` | 板级配置（FD `0xA7100000` + `0x300000`） | |
| `dtb/ishtar.dtb` | 本机 live FDT（`/sys/firmware/fdt`，902,020 B） | 打包后处理步骤需要 |
| `kernel/` | H′ 内核构建套件：`xnu-deps/`、`xnu-build.sh`、`xnu-env.sh`、`xnu-12377.121.6-dada.patch` | 用于编 HakiOS 内核 |
| `.github/workflows/` | `build-ishtar-uefi.yml`（固件）、`build-xnu-ishtar.yml`（内核） | |

## 二、两条流水线

### 1. 固件：`build-ishtar-uefi`

产物：**`SILICIUM_UEFI-ishtar.fd`**，必须正好 **3,145,728 字节（`0x300000`）**。

流程：checkout → 装工具链 → `git clone Mu-Silicium` 并切到 `hakios/BASE` → `build.sh`
→ 四项校验 → 上传产物。

`build.sh` 里七步：钉住子模块到 superproject 记录的 SHA、打两项 hook、放板级包、放 `Binaries/ishtar`、
建 Python 环境、取外部依赖、执行构建。

### 2. 内核：`build-ishtar-kernel`

产物：**`mach.ishtar`**（`mach.development.bcm2837`），用于塞进 XNUP 载荷。

流程：装工具链 → 编 `cctools-port`（宿主 x86_64 → 目标 `aarch64-apple-darwin`，拿到 `ld/nm/otool/strip`）
→ 下 `theos/sdks` 取 `iPhoneOS16.5.sdk` → 拼出 `xnu-deps/setup.sh` 要的 `$THEOS` 布局
→ `git clone apple-oss-distributions/xnu@xnu-12377.121.6` 并打 `xnu-12377.121.6-dada.patch`
→ 跑 `xnu-deps/setup.sh` → `xnu-build.sh -j$(nproc) -k` → 上传内核与日志。

## 三、怎么触发

推送到 `main` 会自动触发；也可以手动：**Actions → 选中流水线 → Run workflow**。

取产物：Actions → 对应 run → Artifacts：

- `SILICIUM_UEFI-ishtar`（`.fd` + `FV/` 目录）
- `mach-ishtar-kernel`（`mach.ishtar`）
- 失败时的 `build-log` / `kernel-build-logs`

## 四、本机侧命令（可选）

```sh
source /517899/toolchain/env.sh          # git / clang / gh 等

# 推送并等待固件构建、自动下载校验
GH_TOKEN=... ./ci/push-and-build.sh

# 只盯某次构建，每 4 分钟一次，成功自动下载产物
GH_TOKEN=... POLL=240 ./ci/watch-build.sh <run-id>
```

> 注意：本机 `github.com:443` 不通（`git push` 会失败），但 `api.github.com` 与 `codeload.github.com` 通，
> 所以本机提交走 **GitHub Git-Data API**（`blobs → trees → commits → PATCH ref`）。

## 五、边界与免责

- 仓库里的厂商二进制来自**本机自己的设备固件**，仅供本机使用，**不要公开**（所以仓库是 private）。
- 本仓库不产生任何刷写动作：`fastboot boot` 只在内存里运行，且需操作者明确同意。
- 相关文档：`../../HP-TREE-REPORT.md`（全过程与踩过的坑）、`../../uefi-ishtar/HOOK-PORT.md`（hook 移植）、
  `../../ROLLBACK-PLAN.md`（回退方案）。
