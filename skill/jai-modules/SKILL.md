---
name: jai-modules
description: Jai modules, libraries and platforms (beta 0.2.032) — #import forms (named import, #import,file/,dir/,string), module search order (-import_dir, local modules/ folder, import_path), #load vs #import, #scope_export/#scope_module/#scope_file, re-exporting, name collisions, #module_parameters and program parameters, a map of all 133 bundled modules with per-OS status, everyday modules (Basic print/FormatInt/String_Builder/arrays, String split/join/trim, File and File_Utilities, Hash_Table and the table_find order change, Command_Line, Process run_command, Random, Math, Unicode, Sort, hashing), C and C++ interop (#foreign, #library ,system ,no_dll, #elsewhere, #c_call callbacks, to_c_string, struct layout, varargs, rpath), BuildCpp, Bindings_Generator, Jai as a static or dynamic library (#program_export, generate_c_header), cross-compiling and the Linux ARM64 triple, WebAssembly, iOS/Android, Curl, vendoring third-party modules. Load before importing or writing Jai modules, using a bundled module, binding a C/C++ library, building Jai as a library, or targeting another platform.
---

# Jai modules, native libraries and platforms

## Ground truth first

- Validated with **beta 0.2.032 (26 Nov 2026)** on macOS arm64 (`~/jai/current/bin/jai-macos`, Xcode `ld`),
  powerslabs (Arch Linux x64, gcc 16 and clang) and ubuntu-laptop (Ubuntu 26.10 x64, gcc 15, **no clang**). The 40
  examples in `examples/jai/jai-modules/` pass on all three; quoted messages are real compiler output. No Windows
  or Linux ARM64 machine was used: those parts are object files only or documented from the bundle.
- Check the version (prints only to a terminal): `script -q /dev/null ~/jai/current/bin/jai-macos -version` or
  `script -qc "~/jai/current/bin/jai-linux -version" /dev/null` (details in the jai skill).
- **The module source is the documentation.** All 133 modules are plain source in `~/jai/current/modules/`.
  Exact signatures: `library_search query="run_command" sources=["jai-modules-src"]`; lessons
  `sources=["jai-how-to"]` (040 import/load, 151 scopes, 380 module parameters, 950 cross-compiling); programs
  `["jai-examples-src"]` (dll, output_types, import_replacement, wasm, ios_library); "when did X change?"
  `["jai-changelog"]`; then `library_read`. Or grep: `grep -n "^table_find ::" ~/jai/current/modules/Hash_Table.jai`.
  **Never guess a name, a parameter or the order of multiple return values**: several changed in 2025–26.
- The bundle is private (Copyright.txt): read it locally, never paste its text or code into public files.
- Deep dives (relative to this skill): `reference/module-map.md` (all 133 modules), `reference/writing-modules.md`,
  `reference/everyday-modules.md`, `reference/c-interop.md`, `reference/bindings-generator.md`,
  `reference/platforms-and-cross-compiling.md`.

## Modules in one screen (deep dive: reference/writing-modules.md)

- A module is code compiled in **its own scope** (it sees Preload and its own imports, never your program), always
  **from source, with your program, every build**. Native code enters only through `#library`. Forms: single file
  `Name.jai`, or folder `Name/module.jai` that `#load`s more files. Both in one directory is an error: *"This
  module exists in both single-file and directory form"* (08).
- `#load "x.jai"` adds a file to the current program or module; `#import` uses another module.

```jai
#import "Basic";                              // every exported name, unqualified
M :: #import "Math";                          // only M: M.Vector3, M.length(v)            (01)
Util   :: #import,file "vendor/util.jai";     // a file as a module; path relative to this file (06)
Shapes :: #import,dir  "vendor/Shapes";       // a folder module by path
#import,string "plus_one :: (x: int) -> int { return x + 1; }";
```

- **Search order** (07, printed from `get_build_options().import_path`): each `-import_dir DIR` (a relative DIR is
  relative to the **first compiled file**), then `modules/` next to the first compiled file (automatic since
  0.1.080), then the compiler's `modules/`. The first match wins **for the whole workspace**: a local
  `modules/Hash.jai` also replaced the Hash that bundled Hash_Table imports. That is how to patch a bundled module
  (copy, edit) and how a generic module name can silently shadow one. Build metaprograms set
  `Build_Options.import_path`; `remap_import` / `provide_import` redirect imports (examples/import_replacement).
- **Imports are not transitive** (04): a module that imports Basic does not give you `print`.
- **Scopes** (02, 03): `#scope_export` (default at the top of every file: the API), `#scope_module` (all files of the
  module, invisible to importers: *"Undeclared identifier 'x'"*), `#scope_file`. Put a module's own `#import`s under
  `#scope_module`.
- **Re-export on purpose** (05): `using Basic :: #import "Basic";` exports Basic's names and `Basic.` itself;
  `say :: Basic.print;` exports one alias.
- `#import` inside a procedure: an unqualified one still links its names at program level (another procedure could
  call `print`); `M :: #import "Math";` there is local to the procedure.

## Name collisions (09, 10)

| Two unqualified imports export... | Result |
|---|---|
| procedures with the same name and different arguments | one overload set: fine |
| procedures with identical argument lists (e.g. Random + PCG `random_get()`) | *"Procedure call matches 2 possible overloads"* |
| the same constant, type or global | *"Redeclaration of 'VERSION'"*, even if never used |
| a name your program also declares | redeclaration; a `#scope_file` declaration in your file shadows the import |

Fix with a named import (`Old :: #import "Old_Format";`) or an import under `#scope_file`. Module authors don't
prefix names; importers choose namespaces.

## Module and program parameters (11–14)

```jai
// modules/Counter/module.jai
#module_parameters (STEP := 1, LABEL := "counter") (VERBOSE := false);   // per import ; whole program
// main program
#import "Counter"()(VERBOSE = true);                   // program parameter, set once
By_Two :: #import "Counter"(STEP = 2, LABEL = "by_two");
#import "Basic"()(ENABLE_ASSERT = false);              // assert() becomes an empty macro everywhere (12)
```

- Each distinct module-parameter list is a **separate compilation** (own globals and code); lists deduplicate only
  when written identically (`(LABEL = "x", STEP = 2)` is another copy). Program parameters reach every import of
  the module, including other modules' plain imports; only the main program may set them, once.
- Inside the module the parameters are constants (`#if VERBOSE`); importers read them via a named import
  (`Feet.SYSTEM`). Types for parameters go in a common block: `#module_parameters (U := Unit.METERS) { Unit :: enum
  { METERS; FEET; } };` callers pass `.FEET`; the block's types are not exported (14).
- Errors: *"Argument name 'SIZ' (number 1) is not found in the module parameters."* (13); wrong type; parameters to
  a module without `#module_parameters`; program parameters from a module; *"Cannot supply program parameters for
  the same module twice."*

## The bundled modules (deep dive: reference/module-map.md)

Import check of all 133 on the three machines: 100 compile everywhere; 4 need a `libGL.so` dev symlink (Simp, GL,
GetRect, GetRect_LeftHanded failed on Ubuntu); 6 Mac-only (Curl, Mail, ImGui, Metal, Objective_C, macOS); 5
Linux-only (Linux, X11, Vulkan, MojoShader, meshoptimizer: the last two ship x86_64-only dylibs); 18 none (Windows
family, Android, `iOS` = `iOS/Toolchain` only, Runtime_Support, metaprogram files, radeon_gpu_analyzer). **The
compiler loads every `#library` while compiling**, so a missing or wrong-architecture native library breaks the
import even if you never call it.

- Core: Basic, String, Hash_Table, File, File_Utilities, Process, Math, Sort, Command_Line, Text_File_Handler,
  Unicode, Random, System, Socket, Thread (jai-systems), Compiler (jai-metaprogramming).
- Data/encoding: Bucket_Array, Bit_Array, Xar, Pool/Flat_Pool, Hash, Base64, Crc, md5, xxHash, meow_hash, lz4,
  Simple_Package, Zip_File_Directory.
- Media/UI: stb_image(_write/_resize), stb_vorbis, freetype, pl_mpeg, Sound_Player, Window_Creation, Input, Gamepad,
  Clipboard, Simp, GetRect_LeftHanded, GL, SDL (= SDL **2**), ImGui (1.89.6).
- Tooling: Bindings_Generator, BuildCpp, generate_c_header, Check, Codex, Jai_Lexer, Program_Print, Rewrite,
  Autorun, Icon (Windows only), MacOS_Bundler, executable_formats, debug_info, Remap_Context.
- Experimental by their own headers: SIMD (placeholders), Soa, Float16, PCG ("untested"), Deep_Copy, Vulkan.

## Everyday modules (deep dive: reference/everyday-modules.md)

| Need | Use (0.2.032) | Ex. |
|---|---|---|
| format | `print("% %\n", a, b)`; `%2` positional; `\%` literal; `FormatInt.{value=x, base=16, minimum_digits=4}`, fixed decimals `FormatFloat.{value=f, trailing_width=2, zero_removal=.NO}` (without `.NO` trailing zeros become spaces: 2.5 → `2.5 `) | 15 |
| build strings | `b: String_Builder; print_to_builder(*b, ...); s := builder_to_string(*b);` `sprint` (heap) / `tprint` (temp) | 16 |
| time | `current_time_monotonic()`, `to_milliseconds(d)`, `to_calendar(t)`, `calendar_to_iso_string`, `seconds_since_init()` | 16 |
| arrays | `array_add`, `array_find -> found, index`, `array_ordered_remove_by_index`, `array_view`, `remove it` in `for`, `NewArray(n, T)` | 17 |
| strings | `split(s, ";",, temp)`, `split_from_left -> found, l, r`, `trim`, `join(..parts, separator=",")`, `replace -> s, n`, `find_index_from_left`, `path_join` | 18 |
| numbers | `to_integer(s) -> v, ok, rest`, `string_to_int(s, 16)`, `string_to_float_new(s) -> ok, v, rest`, `parse_int(*cursor)` | 19 |
| files | `read_entire_file(p) -> data, ok`, `write_entire_file(p, s or *builder)`, `file_open(p, for_writing=true, keep_existing_content=true)`, `make_directory_if_it_does_not_exist(p, recursive=true)`, `visit_files`, `file_list`, `file_modtime` | 20 |
| hash map | `t: Table(K, V);` (no init) `table_set`, **`found, v := table_find(*t, k)`**, `table_find_pointer`, `find_or_add`; struct keys need hash + compare procs | 21 |
| CLI flags | `ok, opts, is_set, free := parse_arguments(Options)`; `-flag` single dash, `@"?help"` notes | 22 |
| subprocess | `r, out, err := run_command("sh", "-c", cmd, capture_and_return_output=true, timeout_ms=200)`; `r.type`, `r.exit_code` | 23 |
| random | `random_seed(12345)`, `random_get()`, `random_get_within_range(lo, hi)`; time seed `random_seed(cast(S128) current_time_monotonic())` | 24 |
| vectors | `Vector3.{1,2,3}`, `cross`, `normalize`, `Quaternion`, `Matrix4` row-major, `inverse(m) -> ok, m` | 25 |
| UTF-8 | `for :utf8_iter s { it }` (not with a named variable), `utf8_next_character(*s)` | 26 |
| config files | `Text_File_Handler`: `start_from_memory/start_file`, `consume_next_line`, `break_by_spaces`, `error(h, ...)` | 27 |
| sort, hash | `quick_sort(arr, cmp or key)`, `intro_sort`, `fnv1a_hash`, `crc64`, `md5`, `base64_encode`, `xxHash.native_XXH64` | 28 |

## C interop (deep dive: reference/c-interop.md)

```jai
geo  :: #library,no_dll "lib/geo";          // only lib/geo.a exists                         (29)
greet :: #library "libgreet";               // ./libgreet.dylib|.so, loaded while compiling  (30)
libc :: #library,system "libc";             // (#system_library still accepted)
Vec2 :: struct { x, y: float32; }           // same members, same order as the C struct
geo_scale :: (v: Vec2, k: float32) -> Vec2 #foreign geo;              // structs by value work
c_strlen  :: (s: *u8) -> u64 #foreign libc "strlen";                  // explicit C symbol
c_printf  :: (fmt: *u8, args: ..Any) -> s32 #foreign libc "printf";   // C varargs
geo_calls: s32 #elsewhere geo;                                        // C global
reducer :: (acc: s32, v: s32, user: *void) -> s32 #c_call {           // callback for C
    push_context { print("%\n", v); }                                 // Jai calls need a context
    return acc + v;
}
```

- `#library "x"` = `x.dylib|x.so|x.dll` (+ static `.a|.lib`), path relative to the declaring file. The compiler
  **dlopens it and resolves symbols at compile time**: static-only needs `,no_dll` (else *"Dynamic library load
  failed"*); bad names give *"Unable to resolve foreign symbol 'x' inside library 'libc'"* (link errors with
  `,no_dll`); `#run` can call it. With both `.a` and `.dylib` present the static one was linked.
- C types: `int` = `s32` (Jai `int` is 64-bit), `size_t` = `u64`, `float` = `float32`, `char*` = `*u8`, function
  pointer = `#type (...) -> T #c_call`, C array parameter = `*T` (fixed arrays by value are rejected), packed struct =
  members with `#align 1` (**not** `#no_padding`, which only drops trailing padding; checked against C `offsetof`, 29).
- Strings: literals pass as `*u8`; computed strings don't (*"Dynamically-computed strings do not cast to *u8; only
  literals do."*, 31): `temp_c_string(s)` / `to_c_string(s)`; back with `to_string(ptr)` (borrow).
- Callbacks must be `#c_call` (*"...must use the C calling convention, but the given procedure is native."*, 32) and
  wrap Jai calls in `push_context { }` (*"Cannot call into a native procedure, from a #c_call procedure, without
  using push_context"*, 33).
- C `printf` output is buffered separately: call libc `fflush(null)` before printing from Jai again (30).
- Run time: macOS executables have `LC_RPATH @loader_path` (BuildCpp gives dylibs `@rpath/...` install names);
  Linux executables have `RUNPATH $ORIGIN`. Give a `.so` a SONAME (`-Wl,-soname,libx.so`) or its absolute build path
  is recorded. Library in `lib/`: `additional_linker_arguments = .["-rpath='$ORIGIN/lib'"]` with the quotes (the
  link line goes through a shell; unquoted `$ORIGIN` became `/lib`, 36).
- Linux `#library,system "foo"` links `-lfoo`: needs the `libfoo.so` dev symlink (*"lld-linux: error: unable to find
  library -lGL"*); a full name like `"libm.so.6"` works without it.

## Jai as a library for C, and Jai DLLs (34, 35)

- `#program_export` + `#c_call` procedures, a `STATIC_LIBRARY` or `DYNAMIC_LIBRARY` workspace, and
  `generate_c_header`: `handle_message(*info, msg)` for every message of that workspace's intercept loop, then
  `generate_header(*info, "x.h")`. The header declares the exports, their structs and
  `__jai_runtime_init(argc, argv)` / `__jai_runtime_fini(ctx)` (call them around everything else).
- C host: compile with **`-std=c17`** (the header's `typedef s8 bool` breaks C23), link with **`-no-pie` on Linux**
  (Jai objects are not PIC: *"relocation R_X86_64_32S ... can not be used when making a PIE object"*), and on macOS
  pass `-mmacosx-version-min=11.0` (Jai's default target). Example 34 does it all from one build.jai.
- Jai DLL for a Jai program (35): build the library workspace first and wait for its COMPLETE (the program's compile
  loads it); declare with `#library,no_static_library` + `#elsewhere`; library procedures that use the context start
  with `Remap_Context()` (import `Remap_Context(VERBOSE = false)`; the default logs every member).

## BuildCpp and Bindings_Generator (36; deep dive: reference/bindings-generator.md)

- `build_cpp_static_lib("lib/geo", "csrc/geo.c", extra = .["-fPIC"], compiler_executable_path = "cc")`,
  `build_cpp_dynamic_lib`, `build_cpp_executable(..., library_files = .["x.a"])`, `build_universal_macos_binary`.
  Default compiler: `$CC`/`$CXX`, else `clang`/`clang++` — **absent on some Linux boxes**: pass
  `compiler_executable_path = "cc"` or set `CXX=g++` (the bundled C++ example then worked on Ubuntu).
- Bindings_Generator ships libclang 21: `opts: Generate_Bindings_Options; array_add(*opts.libraries,
  .{filename="shapes"}); array_add(*opts.source_files, "shapes.h"); generate_bindings(opts, "out.jai")`.
  The library must exist (it checks symbols). Output: structs, enums (prefixes stripped, aliases kept), `#c_call`
  types, `#foreign lib "c_name"`, `#elsewhere` globals, `#define` constants, comments, offset asserts.
  `strip_prefixes` renames types too (`shapes_kind` → `kind` clashed with a parameter `kind`). System headers are
  ignored unless whitelisted. C++: `-x c++`, `#cpp_method`, per-OS mangling.
- Bundled bindings modules keep `generate.jai` next to `bindings.jai` and per-OS library folders: copy that layout.

## Platforms and cross-compiling (37; deep dive: reference/platforms-and-cross-compiling.md)

- `OS`, `CPU`, `OS_IS_UNIX`, `IS_CROSS_COMPILING` are compile-time constants of the **target**:
  `#if OS == { case .WINDOWS; #load "win.jai"; case .LINUX; #load "linux.jai"; case; #assert false; }` — untaken
  branches are not compiled. Guard x64-only code (`#asm`, Machine_X64) with `#if CPU == .X64`; Apple Silicon is
  the default macOS target and rejects x64 `#asm`.
- Cross targets via a workspace with `os_target`/`cpu_target` (checked from macOS and Linux hosts): Linux x64 and
  Windows x64 **object files** work (`output_type = .OBJECT_FILE`, `runtime_support_definitions =
  .ENTRY_POINT_AND_INIT`; link on Linux with `cc -no-pie -o app app.o`); macOS → Linux **executable fails** at link
  (bundled lld in Darwin mode); macOS arm64 → macOS x64 executable works; iOS static library works.
  **Linux ARM64 pitfall**: `cpu_target = .ARM64` alone produced an x86-64 object; set
  `llvm_options.target_system_triple = "aarch64-unknown-linux-gnu"`.
- `#run` while cross-compiling runs target bytecode with host allocators but no file I/O or foreign calls; use
  `#run,host -> string { #import "File"; ... }` for host work (how_to/950).
- WebAssembly (examples/wasm): wasm64 only (Memory64), LLVM, custom allocator via `remap_import`; the built module
  ran in Node 24 once its 24 KB stack was raised to 1 MB.
- Windows needs a Windows SDK + VC redistributable (README; untested). Android needs SDK/NDK/Java
  (`modules/Android/README.txt`). MacOS_Bundler builds an `.app` but wrote an empty Info.plist dictionary.

## Third-party modules (40; reference/writing-modules.md §8–9)

- No package manager: **vendor** a copy into `modules/` (found automatically) or `third_party/` +
  `-import_dir third_party` (or `import_path` in build.jai); pin the commit; keep the folder name its docs expect.
  Checked: rluba's jaison (`jaison-source`) worked unchanged that way.
- Judge freshness: last commit vs CHANGELOG, compile its tests, grep for stale forms (`<<`, `#place`, `#must`, bare
  `Context`, `allocator =` arguments, `#foreign_library`, `value, found := table_find`, `initialized =`, x64 `#asm`
  without a CPU guard). 0.2.032's `initialized` → `initialize` rename broke uniform (`uniform-regex-source`),
  jai-postgres and focus (`focus-editor-source`, GPL-3.0) the week it shipped: rename that argument in your copy
  (focus: 21 `New`/`NewArray` calls, then its release build works).
- Current on 0.2.032: jaison, stubborn (`stubborn-source`), jai-simplehttp (`jai-simplehttp-source`, needs uniform),
  jai-xml (`jai-xml-source`; arm64 needs `(USE_SIMD_STRING_SEARCH = false)`), jai-csv (`jai-csv-source`), hyperserve
  (`hyperserve-source`, unfinished), jai-on-linux (`jai-on-linux-source`, Linux bindings). Find more: `awesome-jai`,
  `jai-community-wiki` (dated), `jai-encyclopedia-of-examples` (current); `the-way-to-jai` (Apache-2.0, dated
  after §8).

## Reading older code in this area (each verified on 0.2.032)

| Old | Now | Since |
|---|---|---|
| `#foreign_library "x"`, `#foreign_system_library "libc"` | `#library "x"`, `#library,system "libc"` — old: *"Invalid toplevel directive name 'foreign_system_library'"* (38) | renamed 0.1.049, removed 0.2.002 |
| `value, found := table_find(*t, k)` | `found, value := ...` — the old order **compiles and swaps silently** (39) | 0.2.018 |
| `init(*table, 64)` / `uninit(*table)` | nothing or `table_resize(*t, 64)` (init warns) / `deinit` | 0.2.029 / 0.1.050 |
| `table_reset` that kept memory | `table_reset_keeping_memory` (`table_reset` frees) | 0.2.029 |
| `NewArray(n, T, initialized = false)` | `initialize = false` (hard error, 40) | 0.2.032 |
| `string_to_float(s) -> f, ok` | `string_to_float_new(s) -> ok, f` (old still works) | 0.2.027 |
| `split(...)` returning temp memory | `split(...,, temp)` | 0.1.080 |
| `to_lower(s)`, `index_of_string`, `concatenate` | `to_lower_copy/in_place`, `find_index_from_left`, `join` | removed 0.1.028 |
| `make_vector3(x, y, z)` | `Vector3.{x, y, z}` | 0.2.002 |
| `visit_files(..., follow_symlinks = b)` | `visit_symlinks`, `follow_directory_symlinks` | 0.1.090 |
| `#import "Tagged_Union"`, `bubble_sort`, `Swap` | language tagged unions, `quick_sort`, `swap` | 0.2.025, 0.2.022 |
| `-plug Name` | `+Name` (jai-metaprogramming) | 0.2.012 |

## Pitfalls (all observed)

- A local or vendored module with a common name (Sort, Hash, String) shadows the bundled one for every importer.
- `Name.jai` next to `Name/` → error; `-import_dir` relative paths are relative to the first file, not the shell.
- Random and PCG (and any two modules with same-signature procedures) can't both be imported unqualified.
- `get_absolute_path` uses `realpath` on Unix: fails for paths that don't exist yet.
- `Hash.get_hash` rejects structs: give Table a hash and compare procedure.
- `Command_Line`: enum values are case-sensitive, `--flag` is rejected by default, `[..]` members are not supported.
- `for :utf8_iter c: s` fails; use `it`. String case functions are ASCII-only.
- `random_seed(current_time_monotonic())` doesn't compile: cast to `S128`.
- Curl: Mac needs `libcurl.dylib` copied next to the exe; Linux bundled libcurl needs OpenSSL 1.1 — use
  `#import "Curl"()(LINUX_USE_SYSTEM_LIBRARY = true)` (worked on Arch; needs the `libcurl.so` symlink).
- Nested `ifx` with integer literals is `s64`: returning it from an `s32` callback fails ("Loss of information").
- `Remap_Context` prints every copied member unless imported with `(VERBOSE = false)`.

## Teaching and probing

- Show a module concept with a two-file project: `main.jai` + `modules/Thing.jai` (no flags needed), then change one
  thing and predict: move a proc under `#scope_module` (03), import twice with reordered parameters (11), add a
  second module exporting the same constant (10), drop `,no_dll` (29), remove `#c_call` from a callback (32).
- Print the search path (in a file that imports Basic):
  `#run { #import "Compiler"; for get_build_options().import_path print("%\n", it); }` (07 does it in a procedure).
- Print what the linker gets: keep `text_output_flags = .OUTPUT_LINK_LINE` (default without `-quiet`), then
  `otool -L` / `readelf -d` the result.

## Examples (`examples/jai/jai-modules/`) and siblings

01 named imports · 02 local modules folder · 03 #scope_module (error) · 04 imports not transitive (error) · 05
re-export · 06 #import,file/dir/string · 07 search order + -import_dir · 08 file/folder clash (error) · 09 overloads
across modules · 10 constant clash (error) · 11 module parameters · 12 Basic program parameters · 13 unknown
parameter (error) · 14 parameter common block · 15 print and format · 16 String_Builder and time · 17 arrays · 18
String · 19 parsing numbers · 20 files and directories · 21 Hash_Table · 22 Command_Line · 23 run_command · 24
Random/PCG · 25 Math · 26 Unicode · 27 Text_File_Handler · 28 sorting and hashing · 29 C static library + layout ·
30 C shared and system libraries · 31–33 C errors (strings, callbacks, push_context) · 34 Jai library called from C
· 35 Jai DLL plugin · 36 Bindings_Generator · 37 per-OS code and cross-compiled objects · 38 `#foreign_library`
(error) · 39 old `table_find` order · 40 vendored module needing the `initialize` fix (error).
Run: `cd oc-knowhow && pixi run jai-examples -- --skill jai-modules` (add `--remote powerslabs --ssh-config
"$OCM_SSH_CONFIG" --kit jai-modules` for Linux).

Siblings: **jai** (language, toolchain, false friends, reading old code), **jai-metaprogramming** (`#run`, workspaces
and build metaprograms, message loops, plugins, Type_Info), **jai-systems** (context, allocators, temporary
storage, threads, profiling, debugging). Contrast: **odin** (`foreign import`, `core:`/`vendor:` packages),
**c-platform** (SDL3/sokol in C), **pixi** (C toolchains on conda-forge if a machine lacks a compiler).
