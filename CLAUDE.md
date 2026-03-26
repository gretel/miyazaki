# Tezuka Firmware — Session Notes

## Active Branches

### `dev` (integration branch on `gretel/miyazaki`)
- 31 commits on top of `origin/main` (F5OEO/tezuka_fw)
- All 9 boards CI-validated: pluto, plutoplus, e200, e310, libre, fishball, fishball7020, nano, signalsdrpro
- Fishball 7020 hardware-validated: kernel 6.12, maia-httpd, waterfall, SSH, benchmark
- DCO: `gretel <code@jitter.eu>`

### Open PRs (gretel:pr/* → F5OEO/tezuka_fw main)

| PR | Branch | Scope |
|----|--------|-------|
| #257 | `pr/build-modernization` | Build infra, tarballs, ccache, maia-wasm, bootgen, U-Boot GCC-14 fix |
| #258 | `pr/ci-matrix` | FPGA consolidation (9→1), CI matrix, artifact naming |
| #259 | `pr/kernel-6.12` | Kernel 6.12, maia-kmod 0.12, cortex-a9 removed from TARGET_OPT, hardening+NEON all boards |
| #260 | `pr/hardening` | OpenSSH (no sandbox), firewall, sysctl, XT_MARK |
| #261 | `pr/tailscale` | Tailscale VPN |
| #262 | `pr/cosmetic` | Web UI, MOTD, VERSIONS |

Each PR targets `main` independently — merge conflicts on defconfig are expected.

## Fork

Renamed from `gretel/tezuka_fw` to **`gretel/miyazaki`** — a friendly critique of the upstream, in the spirit of Miyazaki's relationship with Tezuka. GitHub auto-redirects old URLs.

## Kernel 6.12 Porting — Issues Found & Fixed

### 1. Kernel patches rebase (`0004-ad5660.patch`)
- **Makefile context shifted** — new ADC entries (`AD4000`, `AD_PULSAR`, `AD4695`) changed line offsets
- **`nor->info->id[0]` → `nor->info->id->bytes[0]`** — accessor API changed in spi-nor
- **`CFI_MFR_WINBND` → `CFI_MFR_WINBOND`** — typo fixed in 6.12 kernel headers
- **`\ No newline at end of file`** — removing this marker requires adjusting hunk line counts; keep the marker or fix both the count and the content line
- **`.remove` return type** — new driver files (`ad5660_mp.c`, `mpiio_io.c`) need `void` not `int` on 6.11+

### 2. maia-kmod v0.10.0 API breakage
Upstream maia-sdr (even v0.12.0) hasn't updated for 6.4+ APIs:
- `class_create(THIS_MODULE, name)` → `class_create(name)` (6.4+)
- `ida_simple_get/remove` → `ida_alloc_range/ida_free` (deprecated 6.4+)
- `platform_driver.remove` returns `void` not `int` (6.11+)
- **Fix:** Local patch at `package/maia-kmod/0001-fix-kernel-6.4-compat.patch`

### 3. USB_PHY link failure
- `CONFIG_USB_ULPI` calls `usb_add_phy_dev`/`usb_remove_phy` but doesn't `select USB_PHY`
- `USB_PHY` is `def_bool n` (hidden) — can't set it in defconfig directly
- `USB_ULPI depends on ... || USB_PHY` creates circular dep if you also `select USB_PHY`
- **Fix:** Kernel patch `0006-usb-ulpi-select-usb-phy.patch` — replace `USB_PHY` in `depends on` with `select USB_PHY`

### 4. DTS vendor subdirectory (kernel 6.1+)
- ARM DTS files moved from `arch/arm/boot/dts/` to `arch/arm/boot/dts/xilinx/`
- Buildroot copies custom DTS to top-level `dts/` but kernel Makefile only recurses into vendor subdirs
- **Fix:** Buildroot patch `0003-linux-copy-custom-dts-to-vendor-subdir.patch` — also copy to `xilinx/`
- **Critical detail:** Just copying files isn't enough — must also append `dtb-y +=` rules to `xilinx/Makefile` so the kernel build system knows to compile them
- **Also:** Install step must check `dts/xilinx/` path (added `$(wildcard)` fallback)
- **Patch generation:** Hand-writing Buildroot Makefile patches is error-prone. Generate via actual diff: extract tarball twice, modify one copy, diff. The `$(foreach)` and `$(if)` Make syntax inside patches is extremely sensitive to whitespace.

### 5. `005-maiasdr.patch` — applied cleanly with offset
- Exports `v7_dma_inv_range` and `arm_cache_outer_inv_range` for maia-kmod
- No changes needed

### 6. `0002-extend_freq.patch` — applied cleanly
- AD9361 frequency extension (46.875 MHz - 6 GHz)
- No changes needed

### 7. `0003-Perf-spectre.patch` — applied cleanly
- Disables Spectre mitigation on Cortex-A9
- No changes needed

### 8. maia-wasm version mismatch (CI failure)
- `maia-wasm` was pinned to `c49db1fc` (main branch) while `maia-httpd` was pinned to `2637b59` (sweep branch)
- They live in the same monorepo with Cargo path dependencies — must use the same commit
- Also fixed: `$(shell bash -c ...)` antipattern in build commands, undefined `$(MAIA_WASM_SRCDIR)` variable
- **Fix:** Pin both to sweep commit, use `$(@D)` instead of `$(MAIA_WASM_SRCDIR)`

### 9. U-Boot `arch/arm/Makefile` — `-march=armv5` invalid on GCC 14
- `arch-$(CONFIG_CPU_V7)` has a `cc-option` chain: try `-march=armv7-a`, else `-march=armv7`, else `-march=armv5`
- GCC 14 no longer accepts bare `-march=armv5` (only `armv5t/te/tej` are valid)
- The fallback is hit when `-mcpu=cortex-a9` (from `BR2_TARGET_OPTIMIZATION`) conflicts with `-march=armv7-a` in the cc-option test
- **Fix:** Patch `arch/arm/Makefile` — change `armv5` fallback to `armv5te`. Added to all board patch dirs.
- **Also:** Do NOT put `-mcpu=cortex-a9` in `BR2_TARGET_OPTIMIZATION`. It gets injected into U-Boot via the Buildroot toolchain wrapper, causing the `cc-option -march=armv7-a` test to fail (conflict), then the fallback chain hits invalid `armv5`. The Buildroot wrapper already passes `-mcpu=cortex-a9` separately as `BR_CPU` — no need to duplicate it in `TARGET_OPTIMIZATION`.

## Hardware Testing

### Test board: Fishball 7020
- Board has **factory ADI PlutoSDR firmware** (v0.38, kernel 5.15.0), NOT tezuka upstream v0.2.4
- USB serial login works on factory firmware (`/dev/cu.usbmodem*`, 115200)
- Ethernet: no DHCP lease on either factory or our firmware — board may not have PHY populated, or needs static IP
- First test with our firmware used the wrong build (fishball7010 instead of 7020) — wrong FPGA bitstream and DTB
- Fishball 7020 build verified (90 MB `tezuka.zip`)
- **HARDWARE TESTED: kernel 6.12.0 boots on Fishball 7020** — AD9361 probes, FPGA IIO
  drivers load, Ethernet 1Gbps, USB gadget works, USB serial login works
- **Maia-SDR waterfall + SweepFFT both working** via web browser
- **maia-kmod v0.12.0 validated** (2026-03-25) — bumped from v0.10.0, kernel compat
  patch applies identically (maia-sdr.c unchanged between versions). Module loads,
  recording + rxbuffer devices functional.

### hardening-v2 → dev regression fixes (2026-03-26)

#### Waterfall / maia-httpd not starting at boot
- **Root cause:** `maia-sdr.ko` symbol version mismatch after incremental rebuild
  (Dropbear removal rebuilt kernel, changing symbol CRCs; maia-kmod not rebuilt)
- **Fix:** `maia-kmod-dirclean` + rebuild. Symptom: `disagrees about version of symbol
  device_create_file`. With no `/dev/maia/` devices, maia-httpd crashes immediately:
  `failed to open rxbuffer DMA buffer: No such file or directory`

#### SSH login broken (OpenSSH 10.2 seccomp sandbox)
- **Root cause:** OpenSSH 10.2 seccomp sandbox sends SIGSYS (signal 31) to child
  process on ARM32 (Cortex-A9). The seccomp filter doesn't allow a syscall during
  key exchange. After first crash, `PerSourcePenalties` blocks client IP 90 seconds
  → `Not allowed at this time` / `drop connection: penalty: caused crash`
- **Fix:** `BR2_PACKAGE_OPENSSH_SANDBOX=n` → compiles with `--without-sandbox`
- **Diagnostic:** `grep sshd /var/log/messages` shows `mm_reap: child terminated by signal 31`

#### Tailscale iptables MARK error
- **Root cause:** Kernel missing `CONFIG_NETFILTER_XT_MARK`
- **Fix:** Add `CONFIG_NETFILTER_XT_MARK=y` to `zynq_pluto_linux_defconfig`
- **Error:** `Extension MARK revision 0 not supported, missing kernel module?`

### Upstream tezuka v0.2.4 boot (reference)
- Kernel 6.1.0, toolchain ARM 14.2, model "FISH Ball PlutoSDR Rev.A (Z7010/AD9361)"
- ttyPS0 at MMIO 0xe0001000 (UART1) — `console=ttyPS0` is correct
- Ethernet: RTL8211F Gigabit — Link is Up 1Gbps (PHY IS populated)
- USB gadget: rndis + mass_storage + acm + iio_ffs — works
- maia-sdr.ko loads successfully (out-of-tree module)
- `earlycon: stdout-path /amba@0/uart@E0001000 not found` — warning present even on working upstream, harmless

## Build Environment — OrbStack

### Setup
```bash
orbctl create --arch arm64 ubuntu:22.04 tezuka-build
orb run -m tezuka-build -s
sudo apt-get install -y make gcc g++ zip unzip dfu-util fakeroot u-boot-tools \
  device-tree-compiler mtools bison flex libncurses5-dev libssl-dev bc cpio rsync \
  cmake xz-utils libgmp-dev libmpc-dev libclang-dev wget patch file bzip2 git \
  perl python3 ccache
```

### menuconfig — use a real terminal, not orb run -s
`orb run -m tezuka-build -s` spawns a non-interactive shell. ncurses menuconfig
requires a proper PTY. Use this instead:
```bash
orb run -m tezuka-build --shell bash -c "make -C /Users/tom/src/uhd/tezuka_fw/buildroot O=/home/tom/tezuka-build/output/fishball-7020 menuconfig"
```
Or open a full interactive shell first:
```bash
orb shell -m tezuka-build
make -C /Users/tom/src/uhd/tezuka_fw/buildroot O=/home/tom/tezuka-build/output/fishball-7020 menuconfig
```

### Critical: output on native ext4
```bash
# Output MUST be on Linux filesystem, NOT VirtIO mount
make -C buildroot O=/home/tom/tezuka-build/output/fishball fishball_maiasdr_defconfig
make -C buildroot O=/home/tom/tezuka-build/output/fishball -j$(nproc)
```

**Root cause:** `tic` (ncurses terminfo compiler) uses hashed hex directory names (`61/` instead of `a/`) on VirtIO-mounted macOS APFS (case-insensitive). Buildroot's ncurses install expects letter directories.

### Don't use amd64 VMs
OrbStack's Rosetta x86_64 emulation crashes on OpenSSL assembly (SIGTRAP on SSE2/AES-NI instructions). Always use native arm64.

### Kernel git clone is slow
ADI Linux repo = 12.8M objects (~4GB). First build takes ~20 min. Cached in `dl/` for subsequent builds. Future optimization: switch to tarball download (~200MB).

### Active output directory
Only one output dir: `/home/tom/tezuka-build/output/fishball-7020/` (~13 GB).
Stale dirs (`fishball/`, `fishball-6.12/`, `fishball7020/`) deleted 2026-03-25 to
free ~37 GB. Don't create new output dirs — reuse `fishball-7020` with `defconfig`
when switching configs.

### Bulk storage for build artifacts
Use `/Volumes/MacroSmol/work/tezuka-fw/` for firmware zips and sdimg staging.
The macOS boot volume is chronically low on space (~14 Gi free on 460 Gi).

### SD card flashing workflow
```bash
# 1. Pull sdimg from VM to bulk storage
orb pull -m tezuka-build /home/tom/tezuka-build/output/fishball-7020/images/sdimg/ \
  /Volumes/MacroSmol/work/tezuka-fw/sdimg-7020/

# 2. Copy to SD card (FAT32, mounted at /Volumes/TEZUKA)
cp /Volumes/MacroSmol/work/tezuka-fw/sdimg-7020/* /Volumes/TEZUKA/
# (also copy overclock/ dir recursively)

# 3. Eject
diskutil eject /Volumes/TEZUKA
```
**CRITICAL:** `orb pull` of a directory creates a subdirectory inside the target.
If the target already has files from a previous pull, the new files end up in a
nested subdir (e.g. `sdimg-7020/sdimg/`) while the stale top-level files remain.
Always verify you're copying the correct (latest) files, or wipe the staging dir
before pulling. Getting this wrong means flashing stale firmware — silent boot
failure with no obvious error.

### Bootgen RPATH check breaks Go/Tailscale builds
Buildroot's `host-go-bin` install triggers a scan of all ELF files in `host/bin/`.
The broken `host-bootgen` (v2025.2 built from source) has no RPATH, causing the
check to fail. The system `/usr/bin/bootgen` also fails because it links against
system libs. The only workaround: move bootgen **completely out of host/bin/**
before starting the build (even `.bak` extensions get caught).

```bash
# Before any build that includes Go packages (Tailscale, etc.):
OUTDIR=/home/tom/tezuka-build/output/fishball-7020
mv "$OUTDIR/host/bin/bootgen" /tmp/bootgen.tmp
make -C /Users/tom/src/uhd/tezuka_fw/buildroot O="$OUTDIR" -j$(nproc)
cp /usr/bin/bootgen "$OUTDIR/host/bin/bootgen"
rm /tmp/bootgen.tmp
```

**Root cause:** `host-bootgen` (xilinx_v2025.2) is built from source and links
against `$HOST_DIR/lib/` — but the Xilinx build system produces a binary that
either doesn't set RPATH or sets it incorrectly. The RPATH checker in
`support/scripts/check-host-rpath` scans the entire `host/bin/` directory.

**Proper fix:** A Buildroot patch to `package/bootgen/bootgen.mk` to add
`-Wl,-rpath,$HOST_DIR/lib` to the link flags, or skip the RPATH check for
bootgen. Not yet implemented.

### Incremental builds — don't nuke the output
When iterating on fixes, **never** `rm -rf` the entire output dir. Use targeted rebuilds:
```bash
# Only re-extract buildroot (when buildroot patches change):
rm -rf buildroot && ./getbuildroot.sh

# Only rebuild kernel (when kernel patches/defconfig change):
make -C buildroot O=/home/tom/tezuka-build/output/fishball-7020 linux-dirclean
make -C buildroot O=/home/tom/tezuka-build/output/fishball-7020 -j$(nproc)

# Only rebuild a specific package:
make -C buildroot O=/home/tom/tezuka-build/output/fishball-7020 maia-kmod-dirclean
make -C buildroot O=/home/tom/tezuka-build/output/fishball-7020 -j$(nproc)
```
**Caveat:** If you change `BR2_LINUX_KERNEL_CUSTOM_GIT` → `BR2_LINUX_KERNEL_CUSTOM_TARBALL` (or any major config switch), the old `.config` in the output dir still has the old setting. You must re-run `make ... <defconfig>` to regenerate it — but this does NOT require deleting the output dir. Just `<defconfig>` then `make`.

### Stale `dl/` cache causes git fetches
If switching from `SITE_METHOD=git` to tarball, the old `dl/<pkg>/git/` directory still exists. Buildroot may try to `git fetch` if the output dir's `.config` has the old git config. Fix: re-run `make ... <defconfig>` to regenerate `.config` with the new tarball setting. Or delete only `dl/<pkg>/git/` — not the whole `dl/` dir.

## getbuildroot.sh portability
- macOS `tar` doesn't support `--one-top-level`. Use `mkdir -p dir && tar -xzf file --strip-components=1 -C dir` instead.
- macOS has `shasum -a 256` not `sha256sum`. Script handles both.

## Patch file format gotchas
- `\ No newline at end of file` is a valid patch marker. Don't remove it unless you also adjust the hunk line count AND ensure the next `diff --git` line follows correctly.
- Hunk line counts in `@@ -0,0 +1,N @@` count actual `+` lines. The `\ No newline` marker doesn't count but signals that the preceding line lacks a trailing newline.
- When editing patches, always dry-run test: `patch -p1 --dry-run < file.patch`
- **Never hand-write complex Makefile patches.** Generate them by diffing two copies of the actual file. The `$(foreach)`, `$(if)`, `$(call)` syntax plus tab indentation makes hand-editing extremely error-prone.

## CI Notes
- `GITHUB_TOKEN` is auto-provided, no secrets needed
- `bootgen-xlnx` is in Ubuntu 22.04 universe repo, apt installs fine
- Matrix builds: ~50-80 min per board on GitHub Actions (2 vCPU)
- Kernel git clone is the bottleneck; `BR2_DL_DIR` cache helps on subsequent runs
- ccache cache persisted via `actions/cache` keyed per board + SHA
- CI v1 failed: maia-wasm version mismatch (pinned to wrong commit)
- CI v2 failed: bootgen v2025.2 BIF syntax error in post-image.sh (Buildroot builds its own host-bootgen from xilinx_v2025.2, which has incompatible CLI with the BIF format used by post-image.sh)
- CI v3 failed: bootgen fallback used `command -v bootgen` which found the broken `$HOST_DIR/bin/bootgen` first (it's in PATH). Fixed to use `/usr/bin/bootgen` explicitly.
- CI v4 aborted (took too long, superseded by v5)
- CI v5 running: bootgen fix + QEMU smoke test + ccache key fix (`run_number` not `sha`)
- CI v5 **PASSED** — build (1h3m) + smoke-test (44s). QEMU serial fix needed (`-serial mon:stdio`)

## Bootgen v2025.2 is broken
Buildroot 2026.02 builds `host-bootgen` from `xilinx_v2025.2` source. The resulting binary **cannot parse any command-line arguments at all** — even `bootgen --help` fails with "syntax error". This affects both local builds and CI.
- **Workaround (local):** `cp /usr/bin/bootgen .../host/bin/bootgen` (use system `bootgen-xlnx` from apt)
- **Workaround (CI):** `sudo apt-get install bootgen-xlnx` and ensure `/usr/bin/bootgen` is in PATH before `host/bin/`
- **Workaround (post-image.sh):** Test `$HOST_DIR/bin/bootgen -help`, fall back to `/usr/bin/bootgen` explicitly (not `command -v` which finds the broken one in PATH)
- **Root cause:** Xilinx GitHub issue #37 — pre-generated bison/flex parser files (`bisonflex/bif.tab.cpp`, `bif.yy.cpp`) are out of sync with the grammar source files in the v2025.2 release. The built binary has a corrupt command-line parser. This is NOT platform-specific — it's broken on all architectures.
- **Proper fix needed:** Either pin Buildroot's bootgen to an older version, or add a Buildroot patch that regenerates the parser files from source (requires host-bison, host-flex dependencies)

## rust-wasm version must match host rustc
`rust-wasm` provides the `wasm32-unknown-unknown` std library. If its version doesn't match the Buildroot host `rustc` version, wasm compilation fails with `requires 'sized' lang_item`. 
- Buildroot 2026.02 ships `rustc 1.88.0`
- `rust-wasm` was pinned to `1.86.0` → bumped to `1.88.0`
- **Rule:** After Buildroot version bumps, check `host/bin/rustc --version` and update `RUST_WASM_VERSION` to match

## maia-wasm version mismatch (CI failure)
- `maia-wasm` was pinned to `c49db1fc` (main branch) while `maia-httpd` was pinned to `2637b59` (sweep branch)
- They live in the same monorepo with Cargo path dependencies — must use the same commit
- Also fixed: `$(shell bash -c ...)` antipattern in build commands, undefined `$(MAIA_WASM_SRCDIR)` variable
- **Fix:** Pin both to sweep commit, use `$(@D)` instead of `$(MAIA_WASM_SRCDIR)`

## `$(shell)` antipattern in Buildroot .mk files
All `$(shell bash -c ...)` inside `define ... endef` blocks is WRONG. `$(shell)` is evaluated at Makefile **parse time**, not at build time. Commands inside `define` blocks already run in a shell at build time — just write the commands directly:
```make
# WRONG — runs at parse time, $(@D) is empty:
define FOO_BUILD_CMDS
$(shell bash -c "cd $(@D) && make")
endef

# RIGHT — runs at build time:
define FOO_BUILD_CMDS
	cd $(@D) && make
endef
```
Also: `$(FOO_SRCDIR)` is not a real Buildroot variable. Use `$(@D)` for the package build directory.

## Future Work

See `.opencode/plans/2026-03-21-next-steps.md` for the full plan. Key items:
1. ~~CI pipeline validation~~ (all 9 boards passing on `dev`)
2. ~~Kernel 6.12 bump~~ (hardware-validated on Fishball 7020)
3. ~~Kernel tarball download~~ (4GB git → 200MB tarball)
4. ~~All packages switched from git to tarball~~
5. ~~Upstream maia-kmod kernel compat fixes~~
6. ~~OpenSSH replacing Dropbear~~ (sandbox disabled for ARM32 seccomp bug)
7. ~~Firewall, sysctl tuning, Tailscale~~
8. ~~Web UI revamp, MOTD, VERSIONS~~
9. ~~Hardening + NEON optimization all boards~~ (SSP_STRONG, RELRO_FULL, FORTIFY_SOURCE_2, -mfpu=neon)
10. ~~CI matrix builds + artifact naming~~ (`tezuka-<board>-<rev>`, unzipped)
11. ~~6 upstream PRs~~ (#257–#262, each independent on main)
12. Pin remaining unpinned packages (srt, gr-dvbs2rx, gr-satellite, soapyplutosdr)
13. **U-Boot 2025.01** — REVERTED. Compiles but doesn't boot. Old U-Boot (`90401ce`, 2016.07)
    restored and hardware-validated. Work preserved in git history (`uboot-2025.01` branch).
14. ~~PREEMPT_RT~~ — NOT POSSIBLE on ARM32.
15. Bump hamlib 4.5.5 → 4.7.0
16. Dependency audit (unused packages — rxtools dead since 2019)
17. PLUTOSDR → TEZUKA rename
