---
name: odin
description: Write, build, test and debug Odin programs at expert level — installing the official dev-YYYY-MM releases (LLVM, linker and per-OS needs), packages and collections, every `odin` subcommand (build/run/test/check/doc/strip-semicolon/bundle/report/root), compiler flags (-o modes, -debug, -target/-microarch/-target-features, bounds/assert control, -vet family, -strict-style, sanitizers, build modes, -define/#config, -collection, -linker/-lto, -no-crt, nil/panic default allocators), idioms (procedure groups, using, distinct, bit_set, bit_field, #soa, matrix, or_return/or_else/or_continue, defer, implicit context), core/vendor library map (core:os is the former os2), C interop (foreign import, link_name, #c_vararg, calling conventions), `odin test` with ODIN_TEST_* defines, gdb/lldb/RAD debugging, and reading core sources as the API reference. Load before writing or reviewing Odin code; see odin-performance for allocators/SIMD/profiling and odin-targets for embedded and WebAssembly.
---

# Odin (the language and toolchain)

## Ground truth first

- Odin ships monthly **dev-YYYY-MM** tags (hotfix suffix `a`, `b`…), no semver, and the language and `core:` still
  change between them (breaking-change list at the top of every release note). Validated here: **dev-2026-11a**
  (2026-11-03; `odin version` prints `dev-2026-11-nightly:9a69916`; `odin report` shows the LLVM backend, 20.1.8).
  Verify; don't trust these. Check `odin version`, then read the release notes
  (https://github.com/odin-lang/Odin/releases) for every tag between the code's tag and yours.
- **The source is the documentation.** Signatures, defaults and doc comments live in `$(odin root)/core`, `base`,
  `vendor`. The reference library holds the core/vendor sources at the pinned tag: `library_search` for a proc
  name or concept, or `grep -rn "^name ::" $(odin root)/core/<pkg>` for the exact signature before calling anything.
  https://pkg.odin-lang.org is the rendered version (latest only). Never guess a proc name or parameter order.
- Your memory of Odin is probably stale: e.g. `core:os/os2` became `core:os` (the old API is gone), `-lld` was replaced
  by `-linker:lld`, the attribute is `@(enable_target_feature="avx2")` (singular; the help text says plural, the
  compiler rejects it), `mem.Dynamic_Pool` is `mem.Dynamic_Arena`.

## Install (no conda-forge package; use the official release)

- conda-forge has **no Odin** (Nov 2026). Download the archive from GitHub releases: `odin-linux-amd64-<tag>.tar.gz`,
  `odin-linux-arm64-…`, `odin-macos-arm64-…` (macOS amd64 builds stopped after dev-2026-09), `odin-windows-amd64-….zip`.
  Unpack anywhere; the directory with `odin`, `base/`, `core/`, `vendor/`, `shared/` is `ODIN_ROOT` (`odin root`).
  LLVM is bundled (`libs/libLLVM*`), nothing else to install for codegen.
- **Linking** is not bundled on Unix: Linux and macOS call `clang` from PATH (macOS: Xcode command line tools).
  `ODIN_CLANG_PATH=gcc` works for ordinary Linux builds if clang is missing (validated on Ubuntu 24.04 aarch64);
  or `pixi add clang lld` in a Pixi env and put its `bin` first on PATH. `-linker:lld` needs `ld.lld`, `-linker:mold`
  needs `mold` on PATH (`pixi exec --spec mold` works). WASM targets call `wasm-ld` from PATH (from `lld`).
  `-no-crt` on Linux amd64 assembles the entry stub with `nasm` from PATH (`ODIN_NASM_PATH` failed to spawn).
- Editor: `ols` language server (github.com/DanielGavin/ols) + `odinfmt`; build ols from the same Odin tag.

## Layout, packages, collections

- A **package is a directory**; every `.odin` file in it starts with `package name`. No per-file imports of siblings,
  no cyclic package imports. `odin build .` builds the directory; `odin run file.odin -file` a single file.
- `import "core:fmt"`, `import "vendor:raylib"`, `import "base:runtime"`/`"base:intrinsics"`, relative
  `import "../util"`, own collections `-collection:lib=path/to/lib` → `import "lib:foo"` (also `shared:` = ODIN_ROOT/shared).
- File tags (first lines): `#+build linux, darwin` / `#+build !windows`, `#+private` (package-private file;
  `@(private)` / `@(private="file")` per declaration), `#+vet …`, `#+feature dynamic-literals`, `#+no-instrumentation`,
  `#+lazy`, `#+analysis …`. Platform files by name suffix too: `foo_linux.odin`, `foo_windows_amd64.odin`.
- Entry point `main :: proc()`; exit code via `os.exit(n)`. Compile-time constants `ODIN_OS`, `ODIN_ARCH`, `ODIN_DEBUG`,
  `ODIN_OPTIMIZATION_MODE`, `ODIN_DISABLE_ASSERT`, `ODIN_NO_CRT`, `ODIN_VERSION`, `ODIN_BUILD_MODE`… with `when`.

## Subcommands

`build`, `run` (build+run; args after `--`), `check` (type-check only; fastest CI gate; add `-no-entry-point` for
libraries), `test` (runs `@(test)` procs of the initial package; `-all-packages` for imports too), `doc` (text, or
`-doc-format` → `.odin-doc` binary for tools), `strip-semicolon`, `bundle android`, `version`, `report` (OS/CPU/LLVM
for bug reports), `root`. Per-command help: `odin build -help` — read it for the installed version.

## Flags that matter (dev-2026-11a; accept/reject checked on macOS arm64 and Linux)

- **Optimization**: `-o:none|minimal|size|speed|aggressive` (default `minimal`; `-debug` makes it `none`).
  `-o:speed`/`size` build one LLVM module (`-use-single-module`); none/minimal build per-package modules in parallel
  (`-use-separate-modules`). `-lto:thin|thin-files` (needs lld; worked on Linux, failed with Apple's toolchain).
  `-microarch:native` (or a name; `-microarch:"?"` lists), `-target-features:"avx2,fma"` (`"?"` lists).
- **Debug/safety**: `-debug` (DWARF/PDB, `ODIN_DEBUG=true`), `-no-bounds-check` (whole program; prefer
  `#no_bounds_check` on the hot proc/block), `-disable-assert`, `-no-type-assert`,
  `-sanitize:address|thread|memory` (memory: Linux/FreeBSD only). ASan on macOS failed to link with Apple clang 21
  (`___asan_version_mismatch_check_v8`); `ODIN_CLANG_PATH=<LLVM 22 clang>` fixed it. On a hardened Linux kernel ASan
  aborted (shadow range); gcc-linked ASan on Ubuntu worked and reported leaks.
- **Checks**: `-vet` = `-vet-unused-variables -vet-unused-imports -vet-shadowing -vet-cast -vet-using-stmt
  -vet-when-shadowing`; extra `-vet-using-param -vet-style -vet-semicolon -vet-tabs -vet-unused-procedures`
  (with `-vet-packages:`), newer dataflow checks `-vet-nil-deref -vet-uninitialized -vet-atomic-access`.
  `-strict-style` (1TBS, trailing commas, no semicolons, case alignment), `-warnings-as-errors`. CI: `odin check .
  -vet -strict-style -warnings-as-errors`. The checker also errors on things like a `defer` made unreachable by
  `os.exit` (move the work into a nested proc).
- **Build modes**: `-build-mode:exe|dll|lib|obj|asm|llvm-ir` (llvm-ir needs `-out:` to be a directory, one `.ll`
  per package). `-out:path`, `-no-entry-point`, `-reloc-mode:pic|static`, `-print-linker-flags`,
  `-show-system-calls` (prints the exact clang/lld/nasm/wasm-ld command: first thing to look at on link errors),
  `-extra-linker-flags:"…"`, `-extra-assembler-flags:`, `-keep-temp-files`.
- **Config**: `-define:NAME=value` read with `NAME :: #config(NAME, default)` (bool/int/string/enum);
  `-show-defineables`, `-export-defineables:f.csv`. `-collection:name=dir`.
- **Runtime/CRT**: `-no-crt` (requires `-default-to-nil-allocator` or `-default-to-panic-allocator` AND
  `-no-thread-local` on Unix; `core:fmt`'s OS output and `core:c/libc` can't be used; write via `core:sys/linux`),
  `-default-to-nil-allocator`, `-default-to-panic-allocator`, `-no-thread-local`, `-no-rtti` (freestanding/`-bedrock`
  only), `-bedrock` (no maps, RTTI, i128, init/fini, default collections), `-disable-red-zone` (freestanding),
  `-integer-division-by-zero:trap|zero|self|all-bits`, `-source-code-locations:normal|obfuscated|filename|none`.
- **Linker**: `-linker:default|lld|mold|radlink` (mold Linux, radlink Windows). Cross-OS linking from macOS is not
  supported ("Linking for cross compilation for this platform is not yet supported"; exit 0, no binary!) — build
  `-build-mode:obj` and link with the target toolchain, or build on the target. Windows targets need
  `-windows-sdk-root:` + `-linker:lld`.
- **Diagnostics/compile speed**: `-error-pos-style:unix` (file:line:col for editors/CI), `-json-errors`,
  `-terse-errors`, `-max-error-count:`, `-show-timings`/`-show-more-timings` (+`-export-timings:json
  -export-timings-file:`), `-thread-count:N`, `-export-dependencies:make|json`.
- Gone/never existed: `-lld` (→ `-linker:lld`), `-insert-semicolon`. `-subtarget:` (android, iphone,
  iphonesimulator, playdate) must come after `-target:`.

## Idioms (expert defaults)

- **Errors are values**: multiple returns + enums/unions; `x := f() or_return` propagates (the last return value
  must be a bool/enum/union error and named results are returned as-is), `v := m[k] or_else def`,
  `x := next() or_continue` / `or_break` in loops. `#optional_ok`, `#optional_allocator_error` let callers drop the
  last result. `Maybe(T)`, `union` + `switch v in u`, `x.(T)` / `x.?` type asserts.
- **`defer`** for cleanup (runs at scope end, LIFO; `defer if ok {…}`), `@(deferred_out=proc)` for guard procs.
- **Implicit `context`** (allocator, temp_allocator, logger, assertion_failure_proc, random_generator, user_ptr):
  pass behavior down without parameters; `proc "contextless"` and `proc "c"` have none — set
  `context = runtime.default_context()` inside callbacks from C/JS/interrupts before calling Odin-convention procs.
- **Procedure groups** `to_str :: proc{to_str_int, to_str_f64}` instead of overloading; parametric polymorphism
  `proc(x: $T) where intrinsics.type_is_numeric(T)`, `$N: int` compile-time params, `#caller_location` defaults.
- **Types**: `distinct` (`Meters :: distinct f64`), `enum` + `bit_set[Flag; u8]` (`.A in s`, `card(s)`),
  `bit_field u16 { kind: u8 | 4, count: u16 | 12 }` (packed bits, C-like), `#soa[]T` / `#soa[dynamic]T`
  (struct-of-arrays, still `ps[i].x`), fixed arrays with swizzles (`[3]f32` supports `v.xy`, arithmetic),
  `matrix[R, C]f32` (column-major, `m * v`), `#raw_union`, `#packed`, `#align(N)`, `using` on struct fields
  (`using pos: [2]f32` → `e.x`; avoid `using` statements/params: `-vet` flags them).
- Strings are UTF-8 byte slices (`for r in s` iterates runes; `cstring` for C); maps `map[K]V` with
  `delete_key`, `k in m`; dynamic arrays `[dynamic]T` (`append`, `pop`, `reserve`, `inject_at`). Literal
  dynamic arrays/maps need `#+feature dynamic-literals`.
- Everything that allocates takes `allocator := context.allocator` (or temp); pair `make/new` with `delete/free`, or
  use arenas — see odin-performance.

## Library map (core: = maintained stdlib, vendor: = third-party bindings)

- `base:runtime` (context, allocators, `default_context`), `base:intrinsics` (compiler intrinsics),
  `base:builtin` (docs for builtins). `core:fmt` (`println`, `printf/printfln`, `aprintf` (allocates),
  `tprintf` (temp allocator), `bprintf` (into a buffer), `ctprintf` (temp cstring), `sbprintf` (builder)),
  `core:strings` (Builder, split/join/trim…), `core:strconv`, `core:unicode/utf8`, `core:bytes`, `core:bufio`, `core:io`.
- **`core:os`** = the former `os2` (File, `read_entire_file(path, allocator) -> (data, err)`,
  `write_entire_file`, process, env, dir walker); `core:path/filepath`, `core:time`, `core:flags` (CLI args),
  `core:log` (`context.logger = log.create_console_logger()`), `core:terminal`.
- Containers: `core:slice`, `core:sort`, `core:container/{queue, priority_queue, small_array, bit_array, lru,
  rbtree, avl, intrusive, topological_sort, handle_map, pool, xar}`.
- Concurrency: `core:thread` (create/start/join, `thread.Pool`), `core:sync` (Mutex, RW_Mutex, Wait_Group, Sema,
  atomics `sync.atomic_add`…; `sync/chan`), `core:nbio` (non-blocking/async IO), `core:net`.
- Math/SIMD: `core:math`, `core:math/linalg` (+ `glsl`/`hlsl` aliases), `core:math/rand`, `core:simd` (+ `simd/x86`,
  `simd/arm`), `core:math/big`. Data: `core:encoding/{json, cbor, csv, ini, xml, base64, hex, uuid, varint, endian}`,
  `core:compress` (deflate/inflate rewritten in dev-2026-11), `core:hash`, `core:crypto` (constant-time,
  audited-style primitives), `core:image/{png, qoi, …}`, `core:text/{regex, match, scanner, table, edit, i18n}`, `core:mem` /
  `core:mem/virtual` / `core:mem/tlsf`, `core:prof/spall`, `core:debug/trace`, `core:testing`, `core:reflect`,
  `core:dynlib`, `core:c` + `core:c/libc`, `core:sys/{linux, posix, windows, darwin, wasm/js, wasm/wasi, info, llvm}`.
- `vendor:` bindings with prebuilt libs where needed: `raylib` (+raygui, rlgl), `sdl2`, `sdl3` (+image, mixer, ttf,
  net), `glfw`, `OpenGL`, `vulkan`, `wgpu` (native + browser), `directx`, `darwin/Metal`, `ENet`, `box2d`, `box3d`,
  `miniaudio`, `stb`, `cgltf`, `microui`, `nanovg`, `fontstash`, `lua`, `curl`, `zlib`, `ggpo`, `kb_text_shape`,
  `commonmark`, `wasm/WebGL`. Linux usually needs the system `.so` of SDL/GLFW etc.; check each package's README.
- Examples: `$(odin root)/examples/demo/demo.odin` (language tour, runs) and github.com/odin-lang/examples.

## C interop

```odin
when ODIN_OS == .Windows { foreign import mylib "mylib.lib" } else { foreign import mylib "mylib.a" }
foreign import libc "system:c"                               // system:<name> -> -l<name>
@(default_calling_convention = "c")
foreign mylib {
	vec2_len2  :: proc(v: Vec2) -> f32 ---                    // structs are C layout unless #packed etc.
	call_twice :: proc(f: proc "c" (c.int) -> c.int, x: c.int) -> c.int ---
}
foreign libc { @(link_name = "printf") c_printf :: proc "c" (fmt: cstring, #c_vararg args: ..any) -> c.int --- }
```
- Use `core:c` types (`c.int`, `c.size_t`, `c.char`) and `cstring`; convert with `strings.clone_to_cstring` /
  `fmt.ctprintf` / `string(cs)`. Pass slices as `raw_data(s), len(s)`. Callbacks: `proc "c"` + set `context` inside.
- Calling conventions: `"odin"` (default; hidden context pointer), `"contextless"`, `"c"`/`"cdecl"`, `"system"`
  (stdcall on Win32), `"std"`, `"fastcall"`, `"naked"`. Exports: `@(export, link_name = "name") f :: proc "c" ()`.
  Build a C-callable library with `-build-mode:dll|lib|obj` (+ `-no-entry-point`).
- Generate bindings with `odin-c-bindgen` (Karl Zylinski) or the `foreign` blocks in `vendor:` as a model.
- Validated: static lib + `system:c` printf varargs, callbacks into C (qsort), struct by value, temp cstrings.

## Testing

```odin
@(test)
my_test :: proc(t: ^testing.T) {
	testing.expect_value(t, add(2, 3), 5)
	testing.expectf(t, ok, "bad %v", x)
	log.infof("visible with -define:ODIN_TEST_LOG_LEVEL=info") // logs go through context.logger
}
```
- `odin test .` runs tests in parallel threads with a tracking allocator per test: leaks are printed with their
  allocation site (and the exact `-define:ODIN_TEST_NAMES=…` to rerun) but the run still **passes** unless
  `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true` (exit 1; use it in CI). Other defines: `ODIN_TEST_THREADS=n`,
  `ODIN_TEST_NAMES=pkg.test_a,pkg.test_b`, `ODIN_TEST_RANDOM_SEED=n` (seed printed every run; `context.random_generator`
  is seeded), `ODIN_TEST_TRACK_MEMORY=false`, `ODIN_TEST_ALWAYS_REPORT_MEMORY`, `ODIN_TEST_LOG_LEVEL`,
  `ODIN_TEST_FANCY=false` (plain output for CI logs), `ODIN_TEST_SHORT_LOGS`, `ODIN_TEST_LOG_STATE_CHANGES`,
  `ODIN_TEST_GO_TO_ERROR`. `ODIN_TEST_JSON_REPORT=file` **does not compile in dev-2026-11a** (core/testing/runner.odin
  passes `&{pretty=true}` to a by-value param); check later tags.
- `testing.set_fail_timeout(t, time.Second)`, `testing.cleanup(t, proc, data)`, `testing.fail_now`. Tests live
  in the package (or a `tests/` package importing it); `-all-packages` runs the tests of imported packages.

## Debugging

- Build `-debug` (implies `-o:none`; `-debug -o:speed` works but variables get optimized out). Linux: gdb or lldb;
  macOS: lldb (`lldb ./app` then `b file.odin:42`, `bt`, `frame variable`); Windows: RAD Debugger, RemedyBG, Visual
  Studio (PDB). VS Code: CodeLLDB.
- Pretty printers for strings, slices, dynamic arrays, `#soa`, maps, unions, `any`:
  `base/runtime/odin_debugger.py` — gdb `source <root>/base/runtime/odin_debugger.py` (auto-loads from
  `.debug_gdb_scripts` after `add-auto-load-safe-path`), lldb `command script import <root>/base/runtime/odin_debugger.py`.
- Runtime errors print `file(line:col)` with the message (bounds check, type assertion, `panic`, failed `assert`) and
  trap; `-error-pos-style:unix` for clickable paths. Breakpoint in code: `intrinsics.debug_trap()`; stack traces:
  `core:debug/trace`. Memory bugs: tracking allocator (odin-performance), `-sanitize:address`, valgrind via
  `core:sys/valgrind` hooks.

## Gotchas

- Integer types don't implicitly convert (`int(x)`, `f32(i)`), untyped constants do. `cast(T)x` ≡ `T(x)`;
  `transmute(T)x` reinterprets bits; `auto_cast` exists but avoid it.
- Zero-initialized by default; `x: T = ---` leaves it uninitialized (`-vet-uninitialized` checks reads).
- `for x in arr` copies the element; `for &x in arr` to modify. Slices of temp memory die at `free_all(context.temp_allocator)`.
- Unused imports/variables are only errors with `-vet`; `_ = x` / `_ :: pkg` silence deliberately.
- Map/dynamic array growth reallocates: don't keep pointers into them across `append`/insert; use indices/handles.
