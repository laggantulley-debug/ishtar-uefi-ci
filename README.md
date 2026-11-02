# ishtar UEFI — cloud build

Builds **`SILICIUM_UEFI-ishtar.fd`** (3,145,728 B = 0x300000) for the Xiaomi 13 Ultra (ishtar, SM8550-AB)
from Project-Silicium's Mu-Silicium at the HakiOS base commit, plus:

- `hakios/` — HakiOS's two boot hooks: the `XNUP` payload copy in `BootShim.S`, and `BootManagerLib`
  starting `XnuLoader.c` instead of a boot menu;
- `platform/ishtarPkg/` — the board package (memory map, configuration map, GOP log, key input), with the
  R3/prelink loader (`UniXNUPkg`, `DarwinBootPkg`) removed;
- `binaries/ishtar/` — the vendor DXE drivers **extracted from this unit's own `uefi.img`** (97 modules).
  The public Device-Binaries set differs in 5 of them, `DisplayDxe` among them (panel init data), so it is
  deliberately not used;
- `resources/ishtar.toml` — board config (FD `0xA7100000`+`0x300000`).

Push it, or run **Actions → build-ishtar-uefi → Run workflow**. The artifact is
`SILICIUM_UEFI-ishtar` (the `.fd` plus the `FV/` directory).

`build.sh` does the whole build and can also be run on any x86_64 Linux machine:

```sh
git clone https://github.com/Project-Silicium/Mu-Silicium.git Mu-Silicium
git -C Mu-Silicium checkout "$(cat hakios/BASE)"
MU=$PWD/Mu-Silicium ./build.sh
```

Nothing here is flashed to a phone. See `../../HP-TREE-REPORT.md` and `../../uefi-ishtar/HOOK-PORT.md`.
