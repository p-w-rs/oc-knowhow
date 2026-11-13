---
name: odin-targets
description: Odin on embedded/bare-metal and WebAssembly — the target list (freestanding_amd64_sysv/arm64/arm32/riscv64/wasm32, js_wasm32, wasi_wasm32, wasm64p32, linux_riscv64…), building objects with -build-mode:obj for a C startup file and linker script, Cortex-M via freestanding_arm32 + -microarch:cortex-mX (compiler-rt builtins, -no-thread-local), what the freestanding runtime gives you (nil allocator, trap on exit/panic, no OS output) and what you must supply (context, allocator, assertion proc, memset via -no-crt), memory-mapped I/O with intrinsics.volatile_load/store, interrupt handlers, running in QEMU (virt aarch64 PL011, mps2-an385/an386 Cortex-M3/M4) with semihosting exit codes, and WebAssembly (js_wasm32 with core/sys/wasm/js/odin.js, WebGL/WebGPU, @(export) procs and step(dt), wasi_wasm32 with wasmtime, freestanding_wasm32 libraries, wasm memory/allocator, size optimization with wasm-opt). Load before targeting an MCU, a kernel, or the browser/WASI; language basics in the odin skill.
---

# Odin for embedded and WebAssembly

Validated with Odin **dev-2026-11a** (macOS arm64 host; Linux x86_64 and aarch64 for linking C hosts): Odin ran on
QEMU `virt` aarch64 (PL011 UART), QEMU `mps2-an385` (Cortex-M3) and `mps2-an386` (Cortex-M4F) with SysTick
interrupts, as a freestanding object linked into C programs, as `wasi_wasm32` under wasmtime, as a
`freestanding_wasm32` library, and as a `js_wasm32` WebGL page in Chrome. Targets and runtime behavior change between
releases: run `odin build . -target:"?"` and read `base/runtime/os_specific_freestanding.odin`,
`base/runtime/procs.odin`, `core/sys/wasm/README.md` for your tag. Verify; don't trust these.

## Targets (`-target:"?"`, dev-2026-11a)

- Freestanding (no OS; `ODIN_OS == .Freestanding`): `freestanding_amd64_sysv` (x86_64-pc-none-gnu),
  `freestanding_amd64_win64`, `freestanding_amd64_mingw`, `freestanding_arm64` (aarch64-none-elf),
  `freestanding_arm32` (arm-none-eabihf; Cortex-A/R/M via `-microarch:`), `freestanding_riscv64`
  (riscv64-unknown-gnu, RV64GC, lp64d), `freestanding_wasm32`, `freestanding_wasm64p32`.
  No riscv32, no AVR/Xtensa/MSP430: for those, Odin is not an option (LLVM-IR export won't help with the runtime).
- WASM: `js_wasm32`, `js_wasm64p32` (64-bit ints, 32-bit pointers), `wasi_wasm32`, `wasi_wasm64p32`, `orca_wasm32`.
- OS targets useful for embedded Linux: `linux_arm64`, `linux_arm32`, `linux_riscv64`, plus `-subtarget:android`.
- `-microarch:"?"` and `-target-features:"?"` list CPU names/features for the chosen target (arm32 lists cortex-m0 …
  cortex-m85, cortex-a*, cortex-r*). `-subtarget:playdate` exists for freestanding_arm32 (Cortex-M7).

## Freestanding build recipe

```sh
odin build kernel.odin -file -target:freestanding_arm64 -build-mode:obj -no-crt -o:size \
  -disable-red-zone -reloc-mode:static -target-features:"strict-align" -out:kernel.o
clang --target=aarch64-none-elf -c start.S -o start.o          # vector table / reset / stack / .bss zeroing
ld.lld -T link.ld start.o kernel.o -o kernel.elf                # your linker script; or arm-none-eabi-gcc/ld
qemu-system-aarch64 -M virt -cpu cortex-a72 -nographic -semihosting -kernel kernel.elf
```
- **Odin does not link freestanding executables for you**: build `-build-mode:obj` (one ELF object; `-build-mode:asm`
  / `llvm-ir` to inspect) and link with the board's startup file + linker script (any `ld.lld`, GNU ld, or the vendor
  SDK's toolchain — e.g. drop `kernel.o` into a CMake/Zephyr/STM32Cube/pico-sdk build as an extra object).
  Freestanding implies `-no-entry-point`; export your entry with `@(export, link_name = "kmain") kmain :: proc "c" () -> !`.
- **`-no-crt` is required** unless the image links a libc: with it the runtime defines `memset`/`memcpy`/`memmove`
  itself (validated; without it the link fails with undefined `memset`/`memmove`).
- **aarch64 with the MMU off**: add `-target-features:"strict-align"`; otherwise LLVM emits unaligned accesses and the
  core faults silently (validated: hung after the first UART line inside `fmt`). Enable FP/SIMD (`CPACR_EL1.FPEN`)
  in `start.S` before calling Odin code.
- **Cortex-M** (`-target:freestanding_arm32 -microarch:cortex-m3|m4|m7|m33…`): emits Thumb-2 (checked with
  llvm-objdump). Add `-no-thread-local` (else undefined `__aeabi_read_tp`), and link compiler-rt/libgcc builtins for
  64-bit division and soft/double float (`__aeabi_*`, `__udivdi3`, `__divdf3`…). conda-forge and MacPorts don't ship
  thumbv7m builtins; arm-none-eabi-gcc's `libgcc.a` works, or compile `compiler-rt/lib/builtins/*.c` with
  `clang --target=thumbv7m-none-eabi -mfloat-abi=soft` into a static lib (done here: ~50 files). On M4F/M7 enable the
  FPU in the reset handler (`SCB->CPACR |= 0xF << 20` at `0xE000ED88`) — otherwise the first float instruction
  faults (validated hang). The triple is hard-float EABI; M0/M3 code has no FPU instructions anyway.
- RISC-V: `freestanding_riscv64` objects build (RVC, double-float ABI); boot with OpenSBI/`-M virt -bios none` and a
  `start.S` like the aarch64 one (UART 16550 at 0x10000000). Not run here: no `qemu-system-riscv64` on conda-forge
  or the test hosts. `linux_riscv64 -no-crt -default-to-nil-allocator -no-thread-local -linker:lld` binaries ran under
  `qemu-riscv64` user mode (`pixi exec --spec qemu-execve-riscv64 qemu-riscv64 ./app`).
- x86_64 kernels: `freestanding_amd64_sysv` + `-disable-red-zone` (interrupts clobber the red zone) +
  `-reloc-mode:static`; boot via Multiboot2/Limine; also kernel-mode code must avoid SSE until you enable it.
- Also link freestanding objects into ordinary C programs (plugins, kernels' userland tests): validated on Linux
  x86_64 (clang) and aarch64 (gcc). macOS `ld` rejects ELF objects (`unknown file type`).

## What the freestanding runtime does and doesn't do

- `context.allocator` = **nil allocator on every freestanding target** (the compiler forces
  `ODIN_DEFAULT_TO_NIL_ALLOCATOR` unless `-default-to-panic-allocator`): `make`/`new` return `nil`/`.Out_Of_Memory`;
  no default temp allocator. Give it memory: a static buffer + `mem.Arena`/`mem/tlsf`, set per entry point
  (`context.allocator = mem.arena_allocator(&arena)`), or `-default-to-panic-allocator` to catch hidden allocations.
  No `core:mem/virtual` (no OS pages).
- `_exit` and failed asserts/bounds checks → `trap()`; `default_assertion_contextless_failure_proc` prints nothing on
  freestanding. Install your own: `context.assertion_failure_proc = my_assert` (prints over UART, then halts/resets),
  and keep bounds checks on in debug builds — they become traps you can catch in the HardFault handler/debugger.
- No stdout: `fmt.println` goes nowhere. Format into a buffer with `fmt.bprintf(buf[:], …)` and write it out yourself
  (validated on both boards, including floats). Or implement an `io.Writer` over the UART and use `fmt.wprintf`.
- Every exported/interrupt proc is `proc "c"` with no context: start it with `context = runtime.default_context()`
  (the compiler errors and suggests exactly that) before calling Odin-convention code; keep ISRs `"contextless"`
  when they only touch registers/atomics.
- Globals are zero-initialized in `.bss` (zero it in `start.S`); `@(init)` procs and `.data` initializers need your
  startup code to copy `.data` from flash and call `runtime._startup_runtime()` (see `base/runtime/core.odin`;
  or avoid them: `-disable-init-fini`, `-disable-non-constant-globals`, `-bedrock`).
- Size: the aarch64 demo with `core:fmt` is ~147 KB text at `-o:size`; without fmt a few KB. Trim with
  `-source-code-locations:none|filename`, `-no-rtti` (freestanding allows it), `-disable-assert`, `-no-type-assert`,
  `-bedrock` (no maps/RTTI/i128/default collections).

## Hardware access

```odin
UARTDR :: (^u32)(uintptr(0x0900_0000))           // PL011 data register on QEMU virt
UARTFR :: (^u32)(uintptr(0x0900_0018))
uart_putc :: proc "contextless" (c: byte) {
	for intrinsics.volatile_load(UARTFR) & (1 << 5) != 0 {}   // TXFF
	intrinsics.volatile_store(UARTDR, u32(c))
}
@(export, link_name = "SysTick_Handler")                      // name referenced by the vector table in start.S
systick_handler :: proc "c" () { intrinsics.volatile_store(&ticks, intrinsics.volatile_load(&ticks) + 1) }
```
- MMIO only through `intrinsics.volatile_load/volatile_store` (plain loads get merged/hoisted). Register blocks:
  `#packed`/plain structs of `u32` at a fixed address, `bit_field u32 { … }` for register layouts, `bit_set` for
  flag registers. Barriers: `intrinsics.atomic_thread_fence(.Seq_Cst)` or `dsb/isb` in assembly helpers.
- Shared ISR/main variables: volatile accesses or `sync.atomic_*` (Cortex-M0 has no LDREX/STREX: use critical
  sections). Interrupt enable/disable, `wfi`, semihosting `bkpt 0xab`/`hlt 0xf000`: small `start.S` helpers called as
  `foreign { semihost_call :: proc "c" (op: u32, arg: uintptr) -> u32 --- }`.
- QEMU exits with the program's status via semihosting (`-semihosting`; aarch64 `SYS_EXIT` 0x18 with
  `{0x20026, code}`, arm `bkpt 0xab` with r0=0x18, r1=0x20026): validated `-define:EXIT_CODE=3` → qemu exit 3 — use it
  for CI. Boards validated: `-M virt -cpu cortex-a72` (aarch64, load at 0x40080000), `-M mps2-an385` (M3),
  `-M mps2-an386` (M4F); CMSDK UART0 at 0x40004000 (enable TX in CTRL, poll STATE bit0). QEMU itself is **not** on
  conda-forge (only user-mode `qemu-execve-*`): use the system package (apt/MacPorts) or a container.

## WebAssembly

- **Toolchain**: Odin calls `wasm-ld` from PATH for every wasm target (not bundled on Linux/macOS; Windows ships it in
  `bin/`): `pixi exec --spec lld …` or put LLVM's `wasm-ld` first on PATH. Linker flags Odin adds: `--stack-first
  -z stack-size=1048576 --allow-undefined` (+`--no-entry` with `-no-entry-point`); pass more with
  `-extra-linker-flags:"--export-table --import-memory …"`.
- **js_wasm32** (browser): copy `$(odin root)/core/sys/wasm/js/odin.js` **from the same Odin version** next to the
  `.wasm` and `<script src="odin.js"></script><script>odin.runWasm("app.wasm", consolePreElement)</script>`.
  `runWasm(path, consoleEl, extraForeignImports, memoryInterface, intSize=4|8)` instantiates, calls `_start` (your
  `main`), then calls your `@(export) step :: proc(dt: f64) -> (keep_going: bool)` every animation frame, and `_end`.
  `fmt.println` appears in the console element; imports used: `odin_env` (write, rand_bytes, math), `odin_dom`
  (DOM/events), `webgl`/`webgl2`. Extra JS functions: `foreign import "my_env"` + pass `{my_env: {...}}` as
  `extraForeignImports`.
- `core:sys/wasm/js`: `add_event_listener("canvas", .Click, data, proc(e: js.Event))`, window/document listeners,
  `set_element_value_string`, `get_element_value_f64`, `set_document_title`, `device_pixel_ratio`, gamepad state,
  `evaluate`, `alert`. `vendor:wasm/WebGL` (WebGL1/2: `CreateCurrentContextById("canvas", {})`,
  `CreateProgramFromStrings`, `BufferDataSlice`, `Clear(u32(gl.COLOR_BUFFER_BIT))` — the bit constants are `Enum`
  and need a cast). `vendor:wgpu` works in the browser via its `wgpu.js` (build with
  `-extra-linker-flags:"--export-table"`; set `wgpu.g_context`), `vendor:raylib` has a `wasm` lib folder.
- Exports for JS: `@(export) add :: proc "c" (a, b: i32) -> i32` is callable as `instance.exports.add(2, 40)`
  (validated). Strings/slices cross as pointer+length into `instance.exports.memory`; `odin.WasmMemoryInterface` has
  `loadString`, `loadBytes`, `storeU32`… helpers. Exported procs need `context = runtime.default_context()` if they use
  Odin-convention code (js targets also export `default_context_ptr`).
- **wasi_wasm32**: `os.args`, files in preopened dirs, env, clock, `os.exit(code)` work. Run with `wasmtime run
  --dir data::/data app.wasm alpha beta` or from Python: conda-forge has only `wasmtime-py` (no CLI); validated via
  `pixi exec --spec wasmtime-py --spec python=3.13 python run.py` with `WasiConfig` (`argv`, `preopen_dir`,
  `inherit_stdout`), exit code read from `ExitTrap.code`.
- **freestanding_wasm32**: host-agnostic library, no imports at all (validated 4.5 KB without allocation). Like all
  freestanding targets it defaults to the **nil allocator** — set `context.allocator = runtime.default_wasm_allocator()`
  (the emmalloc port over `memory.grow`; 16 KB module) or use an arena over a static buffer. Build with
  `-build-mode:dll` (or exe + exports).
- Memory: one linear memory exported as `memory`; default allocator on js/wasi = `runtime.default_wasm_allocator()`
  (emmalloc port, grows with `intrinsics.wasm_memory_grow`, never shrinks); stack 1 MiB at the bottom (overflow traps
  instead of corrupting globals). Temp allocator works on js/wasi: `free_all(context.temp_allocator)` at the end of
  `step`. `--import-memory` to share a host-created `WebAssembly.Memory`. Threads: not by default (needs atomics,
  shared memory and COOP/COEP headers: check current support before promising it).
- **Size** (WebGL demo, dev-2026-11a): `-o:size` 196 KB; `-source-code-locations:none` 186 KB; + `-no-bounds-check
  -disable-assert` 181 KB; `-o:speed` 230 KB; `-extra-linker-flags:--strip-all` 189 KB; then `wasm-opt -Oz`
  (`pixi exec --spec binaryen wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext
  --enable-mutable-globals in.wasm -o out.wasm`; without the feature flags wasm-opt rejects Odin's output) 157 KB;
  gzip -9 77 KB. `core:fmt` + RTTI dominate: avoid `fmt` in size-critical modules.
- Serve over HTTP (fetch of `.wasm`; `file://` fails): `pixi exec --spec python python -m http.server 8765`; the
  server must send `application/wasm` (Python's does). Safari/WebKit: build with `-webkit-switch-workaround` (typeid
  JIT crash, issue #6810). Debugging: Chrome DevTools with DWARF (`-debug` + the C/C++ DevTools Support extension),
  `wasm-objdump -x` (wabt on conda-forge) to list imports/exports.

## Checklist for a new board/target

1. `-target` + `-microarch` (+ `-target-features`), confirm with `llvm-objdump -d` / `readelf -A` on the object.
2. `-build-mode:obj -no-crt` (+ `-no-thread-local` on Cortex-M, `-disable-red-zone` on x86_64,
   `strict-align` if unaligned access faults), link with startup + linker script + builtins.
3. Entry `@(export) proc "c"` that sets `context` and an allocator over a static buffer, plus an assertion proc that
   reports over UART.
4. First boot in QEMU with semihosting exit codes in CI; then hardware with a debugger (OpenOCD/probe-rs + gdb; build
   `-debug -o:size` for usable line info).
