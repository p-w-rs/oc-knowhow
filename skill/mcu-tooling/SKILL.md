---
name: mcu-tooling
description: Microcontroller development for the Raspberry Pi Pico 2 W (RP2350, Cortex-M33 + Hazard3 RISC-V, CYW43439 Wi-Fi) and ESP32-S3 (Xtensa LX7), before and after the board arrives — toolchains without system installs (ARM GNU tarball, pico-sdk-tools RISC-V gcc, ESP-IDF install.sh into a folder, Pixi for cmake/ninja/python), pico-sdk 2.x builds (PICO_BOARD=pico2_w, PICO_PLATFORM rp2350-arm-s/rp2350-riscv, pico_cyw43_arch + lwIP, stdio USB/UART, UF2), picotool (info, load -x, BOOTSEL, reboot), probe-rs (list, run, download, attach, gdb, RTT/defmt, chip list; Debug Probe CMSIS-DAP and ESP32-S3 USB-JTAG), esptool 5 (write-flash, merge-bin) and espflash 4 (flash --monitor, save-image), ESP-IDF v6 (set-target, sdkconfig defaults overlays, protocol_examples_common, idf.py qemu), Espressif QEMU for ESP32-S3 with Ethernet and UART-to-pty, Renode (portable, headless, platforms list, renode-test Robot suites; no RP2xxx/ESP32 models), zenoh-pico firmware on both chips (Wi-Fi TCP, UART, USB CDC; ESP-IDF component wrapper) talking to zenohd, and Odin objects linked into pico-sdk. Load before building, flashing, emulating or debugging firmware for these chips.
---

# MCU tooling: Pico 2 W and ESP32-S3

Validated 13 Nov 2026 on Linux x86_64 (no board attached): every build below produced a flashable image, ESP32-S3
firmware **ran in QEMU** and exchanged Zenoh traffic with a host `zenohd` over emulated Ethernet *and* emulated UART,
Renode ran a Zephyr ELF under `renode-test`. Ready-made images, sources and exact flash/test steps:
`oc-knowhow/.local/mcu-ready/README.md`. Related skills: **odin-targets** (freestanding Odin, Cortex-M, QEMU),
**zenoh** (§7 zenoh-pico, serial `zenohd`), **pixi**, **c-networking**, **c-platform**. Library references:
`pico-sdk-source` (hardware_* / pico_* headers with doc comments), `pico-examples-source`, `picotool-source`,
`probe-rs-source`, `renode-source` (platforms, Robot keywords), `esp-idf-docs-source` (docs/en at v6.1),
`espflash-source`, `esptool-source`, `zenoh-pico-source`. `library_search` there for exact function names, Kconfig
symbols and CLI flags before writing them; links: https://probe.rs/docs, https://renode.readthedocs.io,
https://docs.espressif.com/projects/esp-idf/en/v6.1/esp32s3/.

## 0. Versions and where tools come from (as of Nov 2026, verify)

| Tool | Version | Get it (no sudo) |
|---|---|---|
| pico-sdk / pico-examples | **2.3.1** (Sep 2026) / tag `sdk-2.3.1` | `git clone -b 2.3.1 … && git submodule update --init` (**full**, see pitfalls) |
| Arm compiler | ARM GNU **15.2.rel1** | developer.arm.com tarball `arm-gnu-toolchain-15.2.rel1-<host>-arm-none-eabi.tar.xz`; **not on conda-forge** |
| RISC-V compiler (Hazard3) | riscv32-pico-elf gcc 16.1.0 | `pico-sdk-tools` release `v2.3.1-0`: `riscv-toolchain-16-<arch>-lin.tar.gz` |
| picotool | **2.3.1** | `pico-sdk-tools` `picotool-2.3.1-<arch>-lin.tar.gz` (contains `picotoolConfig.cmake`: set `picotool_DIR`) |
| probe-rs | **0.32.0** (Jul 2026) | release `probe-rs-tools-<triple>.tar.xz` (or `cargo install probe-rs-tools` with Pixi `rust`) |
| ESP-IDF | **v6.1** validated (v6.1.1 bug-fix release followed on 13 Nov 2026; prefer it for new work), also v6.0.3, v5.5.6 LTS | `git clone -b v6.1 --depth 1` + `git submodule update --init --depth 1`, `./install.sh esp32s3` |
| esptool | **5.6.0** | bundled in the IDF venv; conda-forge `esptool`; `pixi exec --spec esptool esptool …` |
| espflash | **4.7.0** | release `espflash-<triple>.zip` (no `unzip` on the host? `bsdtar xf`) |
| Espressif QEMU | 9.2.2 `esp-develop-…-20261109`; IDF v6.1 installs `…-20260417` | `python tools/idf_tools.py install qemu-xtensa` |
| Renode | **1.17.0** (Sep 2026) | `renode-1.17.0.linux-portable.tar.gz` (bundles .NET 8), osx-arm64 dmg, deb/rpm |
| zenoh-pico / zenohd | 1.10.2 | see **zenoh** §7 (serial needs a `transport_serial` zenohd) |

conda-forge has `cmake`, `ninja`, `python`, `esptool`, `openocd` 0.12, `libusb`; it has **no** `gcc-arm-none-eabi`,
picotool, probe-rs, espflash or Renode. A Pixi env with `cmake ninja python c-compiler cxx-compiler` (host C++ for
pioasm/picotool builds) + the tarballs above is enough for pico-sdk. ESP-IDF manages its own tools: point
`IDF_TOOLS_PATH` into your work folder (it defaults to `~/.espressif`; v6.1 for esp32s3 = **4.9 GB**) and run
`install.sh` inside a Pixi env that supplies Python 3.12 (the IDF venv is created from that interpreter).

## 1. pico-sdk 2.x for the Pico 2 W

```sh
export PICO_SDK_PATH=$PWD/pico-sdk PICO_TOOLCHAIN_PATH=$PWD/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-eabi
export picotool_DIR=$PWD/picotool            # else the SDK downloads + builds picotool from source
pixi run cmake -S app -B build -G Ninja -DPICO_BOARD=pico2_w -DPICO_PLATFORM=rp2350-arm-s
pixi run cmake --build build                 # build/app.uf2 .elf .bin .hex .dis .map
# Hazard3 cores: PICO_TOOLCHAIN_PATH=<riscv toolchain> -DPICO_PLATFORM=rp2350-riscv  (UF2 family rp2350-riscv)
```
- `PICO_BOARD=pico2_w` selects RP2350A + CYW43 (`boards/pico2_w.h`: LED on CYW43 GPIO 0, `CYW43_WL_GPIO_LED_PIN`).
  The board file sets `PICO_PLATFORM=rp2350`, which resolves to `rp2350-arm-s`; pass `rp2350-riscv` for the Hazard3
  cores; `rp2040` is Pico/Pico W.
- Wi-Fi: link `pico_cyw43_arch_lwip_threadsafe_background` (IRQ-driven, wrap lwIP calls in
  `cyw43_arch_lwip_begin()/end()`), `_poll` (call `cyw43_arch_poll()`), or `_sys_freertos` (FreeRTOS + lwIP sockets;
  what zenoh-pico uses). You must provide `lwipopts.h` (copy `pico-examples/pico_w/wifi/lwipopts_examples_common.h`).
  Join: `cyw43_arch_init()`, `cyw43_arch_enable_sta_mode()`, `cyw43_arch_wifi_connect_timeout_ms(ssid, pw,
  CYW43_AUTH_WPA2_AES_PSK, 30000)` or `_async` + poll `cyw43_tcpip_link_status(&cyw43_state, CYW43_ITF_STA)`.
- stdio: `pico_enable_stdio_usb(t 1)` (USB CDC `/dev/ttyACM0`), `pico_enable_stdio_uart(t 1)` (UART0 GP0/GP1
  115200); `pico_add_extra_outputs(t)` makes the UF2. Measured: blink+Wi-Fi+UDP app 327 KB text Arm, 350 KB RISC-V
  (UF2 647/700 KB); 225 KB of that is the CYW43439 firmware blob `w43439A0_7_95_49_00_combined`. Configure+build from scratch: ~5 s on 24 cores.
- **FreeRTOS** (zenoh-pico's Pico port): `FREERTOS_KERNEL_PATH` = a clone of **raspberrypi/FreeRTOS-Kernel** (has
  `portable/ThirdParty/GCC/RP2350_ARM_NTZ` and `RP2350_RISC-V`), not upstream FreeRTOS.
- Pitfalls (hit): `git clone --depth 1 … --recursive --shallow-submodules` (or `submodule update --depth 1`) on
  pico-sdk left btstack/cyw43/lwip/mbedtls/tinyusb on **branch heads** ("Direct fetching of that commit failed"),
  and CMake only *warned* "LWIP submodule has not been initialized; Pico W wireless support will be unavailable" —
  do a full `git submodule update --init` and check `git submodule status` (2.3.1: cyw43-driver v1.1.1, lwip
  STABLE-2_2_1, mbedtls v3.6.6, tinyusb 0.18.0). `-DCMAKE_C_FLAGS=…` **replaces** the SDK's `-mcpu=cortex-m33
  -mfloat-abi=softfp` (spin_lock.h `#error no SW_SPIN_LOCK_LOCK available`): put extra flags in the `CFLAGS` env
  var or `target_compile_options`. GNU ld 2.45 warns "missing .note.GNU-stack" from newlib: harmless.

## 2. picotool and BOOTSEL

- Without tools: hold BOOTSEL while plugging in → USB drive `RP2350`; copy the `.uf2`. The bootloader checks the UF2
  family (`rp2350-arm-s` vs `rp2350-riscv`) and boots the matching cores.
- `picotool info -a file.uf2` works offline (name, features, pins, SDK version, board, image type "ARM Secure",
  metadata blocks): use it in CI. With a board: `picotool load -x -v app.uf2` (load, verify, run), `-u` skip
  identical sectors, `-f` force a running board with USB stdio into BOOTSEL, `picotool reboot [-u] [-c arm|riscv]`,
  `picotool save -a`, `erase`, `otp`, `partition info`, `uf2 convert`. No board: "No accessible RP-series devices in
  BOOTSEL mode were found." exit 249. Linux non-root: `udev/60-picotool.rules` from the picotool repo.

## 3. probe-rs (debug probes)

- `probe-rs chip list` (0.32.0) contains `RP2040`, `RP235x` (2× Armv8-M, flash 0x10000000, RAM 520 KiB),
  `RP235x_riscv`, `esp32s3` (2× Xtensa) and 24 `esp32*` variants. `probe-rs chip info RP235x`.
- Probes: Raspberry Pi **Debug Probe** (CMSIS-DAP; SWD cable to the Pico 2 W "DEBUG" header + UART on GP0/GP1), any
  CMSIS-DAP/J-Link/ST-Link/FTDI (esp-prog); ESP32-S3's **built-in USB-Serial/JTAG** on its native USB port (no extra
  hardware). Linux: install `69-probe-rs.rules` (probe.rs → Probe Setup) and join `plugdev`; with no probe
  `probe-rs list` says "No debug probes were found" plus udev hints.
- `probe-rs run --chip RP235x app.elf` flashes, resets and streams RTT (`--rtt-up-channels`, `--log-format` for defmt,
  `--target-output-file`, `--catch-hardfault`); pico-sdk C apps print RTT only with `pico_enable_stdio_rtt(t 1)`.
  `probe-rs attach --chip … app.elf` = RTT on a running target. `probe-rs download [--binary-format bin|hex
  --base-address 0x10000000] [--verify] [--chip-erase]`, `reset`, `erase`, `read/write`, `info`.
  `probe-rs gdb --chip RP235x app.elf` → gdb server on **localhost:1337** (`--gdb-connection-string`);
  `arm-none-eabi-gdb app.elf -ex 'target remote :1337'`. `probe-rs dap-server` for VS Code.
- ESP32-S3: `probe-rs run --chip esp32s3 app.elf` builds the IDF image itself (`--idf-bootloader`,
  `--idf-partition-table`, `--idf-flash-mode/--idf-flash-freq`); ESP-IDF's own route is `idf.py openocd` +
  `idf.py gdb` (openocd-esp32 v0.12.0-esp32-20260703, xtensa gdb 17.1).

## 4. ESP-IDF v6.1 for ESP32-S3

```sh
export IDF_TOOLS_PATH=$PWD/idf-tools
pixi run bash -c 'cd esp-idf && ./install.sh esp32s3 && python tools/idf_tools.py install qemu-xtensa'   # ~2 min
pixi run bash -c '. esp-idf/export.sh && cd app && idf.py set-target esp32s3 && idf.py build'          # 13 s hello_world
```
- Separate configs per variant: `idf.py -B build-x -D SDKCONFIG=build-x/sdkconfig -D
  "SDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.qemu" build` (later files override earlier ones). App options in
  `main/Kconfig.projbuild` → `CONFIG_*`. Wi-Fi/Ethernet join: add
  `EXTRA_COMPONENT_DIRS $ENV{IDF_PATH}/examples/common_components/protocol_examples_common` and call
  `example_connect()` after `esp_netif_init()` + `esp_event_loop_create_default()`; SSID/password are
  `CONFIG_EXAMPLE_WIFI_SSID/PASSWORD`. Its `idf_component.yml` pulls `espressif/ethernet_init` (1.4.1) from
  components.espressif.com on the first build (needs internet; keep `dependencies.lock`, `managed_components/` is
  a download cache). `idf_build_set_property(MINIMAL_BUILD ON)` keeps builds small (then list
  `REQUIRES` precisely, e.g. `esp_timer` for `esp_timer_get_time`).
- Flash: the build prints the **esptool 5** command — `python -m esptool --chip esp32s3 -b 460800 --before
  default-reset --after hard-reset write-flash @flash_args` (hyphenated subcommands/values; `write_flash`/
  `default_reset` are the v4 spellings). `idf.py -p /dev/ttyACM0 flash monitor`. Offsets: bootloader **0x0** on S3
  (0x1000 on classic ESP32), partition table 0x8000, app 0x10000. `esptool --chip esp32s3 image-info app.bin` works
  offline.
- espflash 4.7: `espflash flash --chip esp32s3 -p PORT --monitor app.elf` takes the **ELF**; pass the IDF
  `--bootloader bootloader.bin --partition-table partitions.csv` or it uses its own (≈4 MB app partition vs IDF's
  1 MB `factory`). `espflash save-image --chip esp32s3 --merge app.elf out.bin` (offline, validated), `monitor`,
  `board-info`, `list-ports`, `partition-table --to-csv`.

## 5. ESP32-S3 in QEMU (validated)

- `idf.py qemu` (needs `qemu-xtensa` installed) merges a 2–4 MB `qemu_flash.bin`, writes a blank `qemu_efuse.bin` and
  runs `qemu-system-xtensa -M esp32s3 -m 32M -drive file=qemu_flash.bin,if=mtd,format=raw … -global
  driver=timer.esp32s3.timg,property=wdt_disable,value=true -nic user,model=open_eth -nographic -serial mon:stdio`.
  hello_world printed "This is esp32s3 chip with 2 CPU core(s), WiFi/BLE, silicon revision v0.3". Non-interactive:
  `timeout 30 idf.py qemu < /dev/null > log`; `--qemu-extra-args`, `--gdb` (then `idf.py gdb`), `-g` graphics.
- **No Wi-Fi in QEMU**. Networking = the OpenCores MAC: `CONFIG_EXAMPLE_CONNECT_WIFI=n`,
  `CONFIG_EXAMPLE_CONNECT_ETHERNET=y`, `CONFIG_ETHERNET_OPENETH_SUPPORT=y`, `CONFIG_ETHERNET_INTERNAL_SUPPORT=n`,
  `CONFIG_ETHERNET_SPI_SUPPORT=n` → DHCP 10.0.2.15, host = **10.0.2.2**. Errors "add mac address to filter not
  supported / Failed to add multicast filter" are harmless.
- **UART to the host**: a second `-serial pty` becomes UART1 ("char device redirected to /dev/pts/N (label
  serial1)"); first `-serial file:uart0.log` keeps the console. Run QEMU directly (`scripts/qemu-serial.sh` in
  mcu-ready: `esptool merge-bin --pad-to-size=4MB … @flash_args`, 1024-byte zero efuse file).

## 6. Renode (simulation, CI)

- 1.17.0 portable: `renode --disable-gui --plain --console -e "mach create; machine LoadPlatformDescription
  @platforms/cpus/nrf52840.repl; sysbus LoadELF @<url-or-path>; start; …; quit"`. Platforms: ~120 CPUs/SoCs in
  `platforms/cpus` (STM32F0–H7/L/G/WBA, nRF52840, SAM, i.MX RT, Renesas RA, SiFive FE310/FU540, LiteX/VexRiscv,
  OpenTitan, Kendryte K210, `xtensa-sample-controller`, x86…). **No RP2040/RP2350 and no ESP32 models** (grep of
  platforms/scripts: none). RP2040 exists only as the community repo matgla/Renode_RP2040 (not tested); for these two
  chips use Espressif QEMU (ESP32-S3) and hardware (Pico 2 W), and Renode for host-portable logic on a supported MCU.
- `renode-test suite.robot` needs Python deps from `tests/requirements.txt` (robotframework==6.1, psutil, pyyaml,
  telnetlib3, construct, pyelftools); otherwise "No module named 'psutil'". Pixi env: `python=3.12` + those as
  `--pypi`; `pixi run …/renode-test x.robot` (2 tests in 2.7 s, writes `robot_output.xml`, `log.html`, and a
  snapshot + log for failures). Keywords: `Execute Command`, `Create Terminal Tester ${UART} timeout=10
  defaultPauseEmulation=true` (**`timeout=`**, not `defaultTimeout=`: "Arguments types do not match"), `Start
  Emulation`, `Wait For Prompt On Uart`, `Write Line To Uart`, `Wait For Line On Uart`, `Create LED Tester`,
  `Assert LED State`; source `src/Renode/RobotFrameworkEngine/*Keywords.cs`, examples `tests/platforms/*.robot`.
- nRF52840 UART output appeared only with `uart0: easyDMA: false` in the platform string (as the stock test does).

## 7. zenoh-pico firmware (both validated as builds; ESP32-S3 also end-to-end in QEMU)

**Pico 2 W** — upstream `examples/rpi_pico` (FreeRTOS + `pico_cyw43_arch_lwip_sys_freertos`). CMake cache:
`PICO_BOARD=pico2_w`, `WIFI_SSID`, `WIFI_PASSWORD`, `ZENOH_CONFIG_MODE=client|peer`, `ZENOH_CONFIG_CONNECT`,
`ZENOH_CONFIG_LISTEN`, `ZENOH_USB_UART=ON` (zenoh over the board's USB CDC; console moves to UART0). It writes
`include/config.h` **into the source tree**, so build variants one after another. Serial endpoint names
(`src/link/transport/serial/uart_rpi_pico.c`): `uart0_0` (GP0/1), `uart1_0` (4/5), `uart1_1` (8/9), `uart0_1`
(12/13), `uart0_2` (16/17), `usb`; e.g. `serial/uart0_0#baudrate=115200`. **1.10.2 does not compile with GCC ≥ 14 on
lwIP** (`udp_lwip.c:106`: `unsigned int addrlen` vs lwIP `socklen_t` = `u32_t` = `unsigned long` →
`-Wincompatible-pointer-types` is an error): `export CFLAGS=-Wno-error=incompatible-pointer-types`. Sizes: Wi-Fi
z_pub 468 KB text, serial 206 KB, 186 KB bss.

**ESP32-S3** — zenoh-pico ships only PlatformIO glue (`extra_script.py`) and single-file `examples/espidf/*.c`
(SSID "SSID", scouting). Wrapper component (mcu-ready `src/zp_esp32s3/components/zenoh-pico/CMakeLists.txt`):
host-configure zenoh-pico once with `-DZP_PLATFORM=espidf -DFRAG_MAX_SIZE=4096 -DBATCH_UNICAST_SIZE=2048
-DZ_FEATURE_LINK_SERIAL=1` to generate `include/zenoh-pico/config.h`, glob the same sources as its CMakeLists
(api, collections, net, protocol, runtime, session, transport, utils, system/common, link/*) plus the files from
`cmake/platforms/espidf.cmake` (`system/espidf/system.c`, `system/socket/esp32.c`, `tcp_esp32.c`, `udp_esp32.c`,
`uart_espidf.c`), `idf_component_register(… REQUIRES esp_driver_uart esp_timer lwip pthread freertos)`, define
`ZENOH_ESPIDF`. ESP-IDF serial names are **fixed ESP32-classic pins**: `UART_0` TX1/RX3, `UART_1` TX10/RX9, `UART_2`
TX17/RX16 (or `serial/<tx>.<rx>` with those pairs) — on S3 use `UART_1`/`UART_2` (UART0 is the console).
Result: in QEMU over openeth and over UART1↔pty↔`zenohd-serial`, the device's publisher reached a Python subscriber,
host puts reached the device's subscriber and a Python `get` got the device's queryable reply. Before the router
listens the UART open fails (`uart driver error`): retry `z_open` (the config is consumed: rebuild it each try).
Wi-Fi app 922 KB = 88 % of the default 1 MB `factory` partition.

Router side: conda-forge `zenohd` has no serial transport (build with `zenoh/transport_serial`, see **zenoh** §7);
`zenohd -l "serial//dev/ttyACM0#baudrate=115200" -l tcp/0.0.0.0:7447`. Keep router→MCU payloads < 1.4 KB on serial.

## 8. Odin on these chips

- **RP2350 Arm (validated build)**: `odin build odin -target:freestanding_arm32 -microarch:cortex-m33
  -build-mode:obj -no-thread-local -o:size -out:logic.o`, then add `logic.o` to the pico-sdk executable's sources
  (CMake `add_custom_command` OUTPUT logic.o). Object attributes: `Tag_CPU_name cortex-m33`, v8-M.mainline,
  FPv5-SP-D16, no VFP-args tag. pico-sdk compiles `-mfloat-abi=softfp` (default `PICO_HARD_FLOAT_ABI=0`), and Odin's
  `proc "c"` passed `f32` in `r0` (`vmov s0, r0` in the disassembly), so the ABIs matched here; check
  `readelf -A` again if you set `PICO_HARD_FLOAT_ABI=1`.
- **Leave out `-no-crt`** when linking into pico-sdk: with it the object *defines* `memcpy/memset/memmove` and
  replaces newlib's in the whole firmware; without it they (and `__aeabi_*`, `__divdf3`, `__udivdi3`) come from
  newlib/libgcc. Exports: `@(export, link_name="odin_led_state") proc "c" (tick: u32) -> bool`; procs that use
  `fmt` need `context = runtime.default_context()` and a buffer (`fmt.bprintf(buf[:cap], …)`); `core:fmt` added
  126 KB text. Freestanding defaults to the nil allocator (see **odin-targets**).
- **No Odin** for RP2350 RISC-V (pico-sdk compiles `-march=rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb -mabi=ilp32`; Odin has only
  `freestanding_riscv64`) or ESP32-S3 (no Xtensa
  backend). There: C, or Rust (esp-hal / rp235x-hal with probe-rs).

## 9. Checklist when the board arrives

1. Flash the known-good image first (`pico2w_udp-arm.uf2` / `hello_world`) to prove cable, port and permissions.
2. Linux permissions: picotool and probe-rs udev rules, `dialout`/`uucp` group for `/dev/ttyACM*`/`/dev/ttyUSB*`.
3. ESP32-S3 boards: native USB = USB-Serial/JTAG (`/dev/ttyACM0`, probe-rs works), UART port = `/dev/ttyUSB0`;
   BOOT+RST if auto-reset fails. Pico: BOOTSEL; `picotool load -f` once USB stdio code runs.
4. Rebuild Wi-Fi images with the real SSID/router IP; open TCP 7447 on the router host.
5. Serial zenoh: 3.3 V USB-UART, cross TX/RX, common GND, 115200; `zenohd` with `transport_serial`.
