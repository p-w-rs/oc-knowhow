# Module map: the 133 bundled modules (beta 0.2.032)

Everything in `~/jai/current/modules/` with what it is for, its state and where it works. Descriptions are
summaries written for this skill; for exact signatures read the module source (`library_search ...
sources=["jai-modules-src"]`, or `grep -n "^name ::" ~/jai/current/modules/<Module>/*.jai`).

**Import check** (27 Nov 2026): every module was compiled as `#import "X"; main :: () {}` on macOS arm64 (Mac),
powerslabs (Arch Linux x64) and ubuntu-laptop (Ubuntu 26.10 x64). Column *Import*: `all` = compiled on all three;
otherwise the machines where it compiled, with the reason it failed elsewhere. Remember that the compiler
**loads every `#library` while compiling** (dlopen + symbol lookup), so a module whose native library is missing,
built for another CPU, or depends on an absent `.so` fails to compile even if you never call it.

Totals: 100 import everywhere, 4 on Mac + powerslabs only (ubuntu-laptop has `libGL.so.1` but no `libGL.so`
development symlink), 6 on the Mac only, 5 on Linux only, 18 on none of the three (Windows-only, Android,
metaprogram files, special modules).

Maturity labels: **core** = used by most programs, maintained; **solid** = maintained, narrower;
**experimental/old** = the module itself says it is unfinished, untested or kept for old code;
**bindings** = thin generated wrappers over a C API.

---

## 1. Language support and the runtime (normally not imported by hand)

| Module | What it is | Import | Notes |
|---|---|---|---|
| `Preload.jai` | Declarations the compiler needs before anything else: `Operating_System_Tag`, `CPU_Tag`, `Type_Info*`, `Allocator`, `Log_Info`, `Source_Code_Location`, memcpy/memset and atomic intrinsics | all | Loaded automatically; read it to learn the OS/CPU enums (`.WINDOWS .LINUX .MACOS .ANDROID .IOS .WASM .PS5 .NN_SWITCH2 ...`, CPU `.X64 .ARM64 .CUSTOM`). |
| `Runtime_Support.jai` | Entry point, runtime init/fini, bounds-check and panic handlers, `OS_IS_UNIX` | none (direct import) | Imported by the compiler with three module parameters; a bare import fails "Not enough module parameters". Replaceable per program. |
| `Runtime_Support_Crash_Handler.jai` | Crash/signal handler that prints a stack trace | all | Pulled in unless `-no_backtrace_on_crash` / `backtrace_on_crash = .OFF`. |
| `Default_Allocator` | The default heap (a trimmed rpmalloc on x64, a simpler one elsewhere) | all | Module parameters `ENABLE_ASSERTS`, `ENABLE_VALIDATE_ARGS`; replace it with `remap_import` (examples/wasm does). Allocators: see jai-systems. |
| `Default_Metaprogram.jai` | What runs when you type `jai file.jai`: parses the command line (`-import_dir`, `-o`, `+Plugin`, `- args`), creates the target workspace | none (it is a metaprogram) | Read it for the exact flags; `-help` text lives here. |
| `Minimal_Metaprogram.jai` | Smaller copy of the above without plugins | none (hangs if imported) | A starting point for your own metaprogram. |
| `Metaprogram_Plugins.jai` | Loads `+Name` plugin modules and calls their `get_plugin()` | all | jai-metaprogramming. |
| `Example_Plugin.jai` | Template of a metaprogram plugin | all | jai-metaprogramming. |

## 2. Everyday: Basic, text, containers, files, processes

| Module | What it is for | Import | Maturity / notes |
|---|---|---|---|
| `Basic` | print/sprint/tprint/log, `String_Builder`, `FormatInt/FormatFloat`, `New/NewArray/free`, `array_*`, temporary storage, `assert`, `Apollo_Time` (time and calendar), `to_integer/string_to_int/string_to_float(_new)`, `to_c_string/temp_c_string/to_string`, `exit`, `sleep_milliseconds`, `get_command_line_arguments`, Int128 | all | **core**. Program parameters: `ENABLE_ASSERT`, `MEMORY_DEBUGGER`, `VISUALIZE_MEMORY_DEBUGGER`, `TEMP_ALLOCATOR_OVERWRITE_MEMORY`, `MEMORY_DEBUGGER_REPORT_ASSERTS`, `REPLACEMENT_INTERFACE`. → everyday-modules.md |
| `String` | split/join/trim/contains/find_index_*/replace/case/compare, `path_*` helpers incl. `path_join`, `scan2`, `parse_int/parse_float/parse_token` on a `*string` cursor | all | **core**. Case functions are ASCII-only. |
| `Unicode.jai` | UTF-8 ⇄ UTF-32: `character_utf8_to_utf32`, `character_utf32_to_utf8`, `utf8_next_character`, `utf8_iter` for_expansion | all | solid; `for :utf8_iter s` only with the implicit `it`. |
| `Hash_Table.jai` | `Table(K, V, hash, compare, LOAD_FACTOR_PERCENT, REFILL_REMOVED)`: open addressing, `table_add/set/find/find_pointer/remove/find_or_add/table_resize/table_reset(_keeping_memory)` | all | **core**. `table_find` returns `(found, value)` since 0.2.018. |
| `Hash.jai` | Hash functions used by Hash_Table: `get_hash` (ints, floats, bools, enums, pointers, strings, arrays), `fnv1a_hash`, `djb2_hash`, `sdbm_hash`, `knuth_hash` | all | solid; struct keys need your own hash. |
| `Bucket_Array.jai` | Array of fixed-size buckets: stable element addresses, O(1) removal by locator | all | solid. |
| `Bit_Array.jai` | Packed bit set with `set_bit/clear_bit/toggle`, for_expansion | all | solid. |
| `Xar` | Andrew Reece's exponential array: chunked, stable pointers, constant-time index | all | new (0.2.016). |
| `Pool.jai`, `Flat_Pool.jai` | Arena allocators (Flat_Pool reserves virtual memory) | all | solid; details in jai-systems. |
| `Relative_Pointers.jai` | Relative pointer/string helper types (replaces the removed language feature) | all | solid, niche. |
| `Deep_Copy.jai` | Copy a data structure and everything it points to | all | experimental (header lists known gaps). |
| `Sort.jai` | `quick_sort` (compare, key, or compare + user data), `compare_floats`, `compare_strings` | all | solid. |
| `IntroSort.jai` | `intro_sort`, `insertion_sort` | all | solid. |
| `RadixSort.jai` | Radix sort of u32/u64/float keys producing ranks | all | old (header apologises for the code). |
| `Command_Line.jai` | `parse_arguments(Struct)`: flags from struct members, `@"?help"` notes, `Is_Set`, free arguments | all | solid. |
| `Text_File_Handler` | Line-based custom file formats: version line, comments, line numbers, errors with location | all | solid. |
| `File` | Open/read/write/seek/flush, `read_entire_file`, `write_entire_file`, `make_directory_if_it_does_not_exist`, `delete_directory`, `file_move/delete/link`, `get_absolute_path` | all | **core**. |
| `File_Utilities` | `visit_files`, `file_list`, `file_exists`, `is_directory`, `copy_file`, `copy_directory`, `file_modtime(_and_size)`, atomic replace, `Path` parsing | all | **core**. |
| `File_Watcher` | Watch directories for changes (inotify / FSEvents / Windows); `init`, `add_directories`, `process_changes` | all | solid. |
| `Process` | `run_command` (capture, timeout, working dir), `create_process`, `read_from_process`, `write_to_process`, `kill_process` | all | **core**. |
| `System.jai` | `get_number_of_processors`, `get_path_of_running_executable`, `get_home_directory`, `get_username`, `get_machinename`, `get_error_value_and_string` | all | solid. |
| `Print_Vars.jai` | `print_vars(x, y.z)` prints expressions with their source text | all | handy for debugging. |
| `Print_Color.jai` | `print_color` with ANSI / Windows console colors | all | solid. |
| `Reflection.jai` | Runtime type-info helpers: enum name ⇄ value, struct field lookup, setting values from strings | all | solid (jai-metaprogramming covers Type_Info). |
| `Simple_Package` | A simple archive format (create, add files, load table of contents) | all | solid. |
| `Zip_File_Directory.jai` | Read the table of contents of a (non-zip64) zip file | all | minimal by design. |
| `Subtitles.jai` | A subtitle file format used by Thekla's engine | all | changing (0.2.031 broke its API; may leave modules/). |
| `Shared_Memory_Channel` | Fast message channel between processes via shared memory | all | solid (example: start read, then write). |
| `Treemap.jai` | Squarified treemap layout (no rendering) | all | solid, niche. |

## 3. Math, numbers, randomness, color

| Module | What it is for | Import | Notes |
|---|---|---|---|
| `Math` | Vector2/3/4 (with `#overlay` swizzle views), Quaternion, Matrix2/3/4/4x3 (row-major `_11.._44`), operators, dot/cross/length/normalize/lerp/slerp, projection/look-at/translation/scale matrices, `inverse` (success first), trig (cephes), PI/TAU, Plane3 | all | **core**. `make_vector3(x, y, z)` removed: use `Vector3.{x, y, z}`. |
| `Sloppy_Math.jai` | `values_are_close`, `is_approximately_zero`, `max_of_type` | all | small helpers. |
| `Float16.jai` | float16 ⇄ float32 conversions for scalars, vectors and matrices (`Float16 :: #type,isa u16`) | all | its header calls it an unfinished starting point. |
| `Random.jai` | 128-bit-state MCG; default state in `context.random_state` (per thread); `random_seed/random_get/random_get_zero_to_one/random_get_within_range` | all | solid. Seed with time: `random_seed(cast(S128) current_time_monotonic())`. |
| `PCG.jai` | PCG32 with the same procedure names | all | header: untested. Never import together with Random unqualified. |
| `Srgb.jai` | sRGB ⇄ linear conversions | all | small. |
| `Color_Interpolation.jai` | Color gradients in RGB/HSV/OKLAB | all | from GetRect. |
| `Bit_Operations.jai` | `popcount`, `bit_scan_forward/reverse`, `byte_swap` | all | x64 uses `#asm`, portable fallback otherwise. |
| `Atomics.jai` | `atomic_add/increment/...` and aliases of the atomic intrinsics | all | jai-systems. |
| `SIMD.jai` | Prototype of portable SIMD operations | all | **experimental**: placeholders, not real intrinsics yet. |
| `Soa.jai` | Struct-of-arrays experiment | all | **experimental**: its header says not to use it for real work yet. |
| `Machine_X64.jai` | CPUID (`get_cpu_info`, `check_feature(info.feature_leaves, .AVX2)`), fences, x86 machine options | all (compiles on arm64 too) | Calls only work on x64: guard with `#if CPU == .X64`. |

## 4. Hashing, checksums, compression, encodings

| Module | What it is for | Import | Notes |
|---|---|---|---|
| `Base64.jai` | `base64_encode/decode`, URL-safe variants | all | verified against system `base64`. |
| `Crc.jai` | `crc64(string)` (CRC-64/WE) | all | verified against a reference implementation. |
| `md5.jai` | `md5(string) -> hex string` | all | verified against system `md5`. |
| `xxHash` | XXH32/XXH64 in pure Jai (`native_XXH64`, streaming state) | all | version 0.7.0; matches python-xxhash. |
| `meow_hash` | Port of Casey Muratori's Meow hash (AES-NI) | all | x64-oriented. |
| `lz4` | LZ4 1.x bindings + prebuilt libraries (`lz4/macos|linux|windows/lib`) | all | bindings (generate.jai included). |
| `Adpcm.jai`, `Wav_File.jai` | IMA ADPCM decode/encode, WAV header parsing | all | used by Sound_Player. |

## 5. Media: images, fonts, audio, video

| Module | What it is for | Import | Notes |
|---|---|---|---|
| `stb_image` | Load PNG/JPG/TGA/BMP/... (`stbi_load`, `stbi_load_from_memory`) | all | bindings + prebuilt libs per OS; `generate.jai` rebuilds them. |
| `stb_image_write` | Write PNG/BMP/TGA/JPG | all | bindings. |
| `stb_image_resize` | Resize images | all | bindings. |
| `stb_vorbis` | Decode Ogg Vorbis | all | bindings. |
| `freetype` | FreeType 2 font rasterizer | all | bindings + prebuilt libs; `freetype-2.12.1` is a deprecated alias module. |
| `freetype-2.12.1` | Old name, forwards to `freetype` with a deprecation | all | update imports to `freetype`. |
| `nvtt` | NVIDIA Texture Tools bindings (texture compression) | all | bindings + libs. |
| `Ico_File.jai` | Build `.ico` files | none | imports Windows_Resources → Windows-only in practice. |
| `pl_mpeg` | MPEG-1 video + MP2 audio decoder ported to Jai | all | pure Jai. |
| `Sound_Player` | Mixing/streaming audio playback (backends in `os/`: CoreAudio, ALSA, DirectSound on Windows, AAudio) | all | solid; audio device needed at run time. |

## 6. Windows, input, 2D/3D drawing, UI

| Module | What it is for | Import | Notes |
|---|---|---|---|
| `Window_Creation` | `create_window`, `toggle_fullscreen`, `set_window_title` (0.2.031) per OS | all | **core** for GUI programs. |
| `Window_Type.jai` | `Window_Type` per OS (HWND, X11 Window, NSWindow pointer, ...) | all | small. |
| `Input` | Events, key/mouse state per frame (`update_window_events`, `events_this_frame`, `input_button_states`) | all | solid; program parameters for X11 touch, consoles. |
| `Gamepad` | Controllers (GameController framework, evdev, XInput) | all | ships `libevdev` for Linux. |
| `Keymap` | Key bindings loaded from files (sections, procs, mouse buttons) | all | undocumented; read its examples. |
| `Clipboard` | `os_clipboard_get_text/set_text/set_bitmap` | all | solid. |
| `Simp` | Simple 2D/3D immediate-mode renderer on OpenGL (`prepare_window`, `set_render_target`, `immediate_*`, textures, fonts, shaders) | Mac, powerslabs (ubuntu-laptop: no `libGL.so` symlink) | **core** for small graphics programs. |
| `GetRect_LeftHanded` | Immediate-mode UI widgets (buttons, sliders, text input, dropdowns, color picker, subwindows) on Simp | Mac, powerslabs | preferred over GetRect. |
| `GetRect` | Same, right-handed coordinates | Mac, powerslabs | to be renamed GetRect_RightHanded. |
| `GL` | OpenGL bindings (glad) + context helpers | Mac, powerslabs | bindings. |
| `ImGui` | Dear ImGui 1.89.6 bindings + prebuilt libs | Mac only | Linux link fails: `undefined symbol: cosf` (missing libm on the link line). |
| `SDL` | SDL **2** bindings | all | system SDL2 needed at run time. For SDL3 see the c-platform skill. |
| `X11` | X11 bindings and globals used by Window_Creation/Input on Linux | Linux | Mac lacks libX11. |
| `Vulkan` | Vulkan 1.1 bindings | Linux (Mac: `#assert` unsupported OS) | header warns: mostly unused and untested; its example asserts on non-Windows. |
| `Metal` | Metal API bindings | Mac only | |
| `Objective_C` | Objective-C runtime + AppKit/Foundation/CoreGraphics/GameController wrappers, defining classes from Jai structs | Mac only | |
| `MojoShader` | Shader translation bindings | Linux (Mac: bundled dylib is x86_64 only) | its example is stale (use before declaration). |
| `meshoptimizer` | Mesh optimization bindings (v0.11) | Linux (Mac: bundled dylib is x86_64 only) | bindings. |
| `d3d11`, `d3d12`, `dxgi`, `d3d_compiler`, `dxc_compiler` | Direct3D 11/12, DXGI, shader compilers | none (Windows-only) | bindings, generate.jai included. |
| `nvidia_aftermath` | NVIDIA GPU crash dumps (D3D12) | none (Windows-only) | bindings. |
| `radeon_gpu_analyzer` | AMD shader analysis | none | imports a `d3d12_agility_sdk` module that is not shipped. |
| `Iprof` | Instrumenting profiler (plugin `+Iprof`, GUI or text reports) | all | jai-systems. |
| `telemetry3` | RAD Telemetry bindings (Windows library) | all (compiles; `ENABLED := false` by default) | needs the commercial library. |

## 7. Networking

| Module | What it is for | Import | Notes |
|---|---|---|---|
| `Socket` | BSD sockets/Winsock bindings + helpers (`bind`, `accept`, `set_blocking`, `set_keepalive`, address to string) | all | solid; generated per OS. |
| `Curl` | libcurl bindings + bundled libcurl | **Mac only** | Mac: works only if `modules/Curl/macos/lib/libcurl.dylib` is copied next to the executable (dyld `@rpath`). Linux: bundled `libcurl.so` needs `libssl.so.1.1` (fails on current distros); `#import "Curl"()(LINUX_USE_SYSTEM_LIBRARY = true)` uses the system libcurl: worked on Arch, failed on Ubuntu without the `libcurl.so` dev symlink. |
| `Mail.jai` | `mail_send` (SMTP via Curl, attachments, HTML) | Mac only | inherits Curl's problems. |

## 8. Platform APIs

| Module | What it is for | Import | Notes |
|---|---|---|---|
| `POSIX` | Shared POSIX bindings (errno, files, pthreads, signals, ...) for Linux/macOS/Android | all | `#assert` on other OSes. |
| `Linux` | Linux-only APIs: inotify, epoll, io_uring | Linux | Mac: symbol `inotify_init1` not found. |
| `macOS` | CoreFoundation/CoreServices/mach/kevent bindings, `Toolchain.jai` (xcrun helpers) | Mac only | |
| `Windows.jai`, `Windows_Utf8.jai`, `Windows_Registry.jai`, `Windows_Resources.jai` | Win32 API, UTF-8 ⇄ UTF-16, registry, embedding icons/manifests into an exe | none (Windows-only) | `Windows.jai` still carries some `#deprecated` bindings. |
| `Android` | NDK bindings (EGL, GLES, Jni, AAudio, Log, Native_App, camera, media), `Android/Toolchain` | none on desktop | import submodules as `#import "Android/EGL"`; needs SDK/NDK. |
| `iOS` | `iOS/Toolchain.jai` only (SDK paths, target triples) | none (no `module.jai`) | `#import "iOS/Toolchain"`. examples/ios_library builds a static library. |
| `Debug` | Backtraces, `breakpoint()`, attach to debugger, signal handlers | all | `USE_GRAPHICS` parameter (X11 message box on Linux). |

## 9. Tooling: compiler plugins, code generation, build helpers

| Module | What it is for | Import | Notes |
|---|---|---|---|
| `Compiler` | Workspaces, `Build_Options`, message loop, `add_build_file/string`, `compiler_*` | all | jai-metaprogramming. |
| `Bindings_Generator` | Generate Jai bindings from C/C++ headers with the bundled libclang 21 | all | → bindings-generator.md. |
| `BuildCpp` | Compile C/C++ into static/dynamic libraries, executables or objects from a metaprogram (`build_cpp_static_lib/dynamic_lib/executable`, `build_universal_macos_binary`) | all | uses `$CC`/`$CXX`, else `clang`/`clang++`; pass `compiler_executable_path = "cc"` where clang is absent. Windows: finds MSVC. |
| `generate_c_header.jai` | Write a C header for `#program_export` procedures and their types | all | → c-interop.md. |
| `Check` | The default checker plugin (print argument counts, binding checks, C-porting warnings) | all | runs unless `-no_check`. |
| `Codex` | Serialize program information for external tools (`USAGE_MODE` READ/WRITE) | all | jai-metaprogramming. |
| `Code_Visit` | Walk Code_Node trees | all | jai-metaprogramming. |
| `Jai_Lexer` | Jai lexer written in Jai | all | used by tools. |
| `Program_Print` | Print the program back from the AST (`+Program_Print`) | all | jai-metaprogramming. |
| `Rewrite.jai` | `+Rewrite` plugin that converts old `<<` dereferences | all | jai skill. |
| `Performance_Report.jai` | `+Performance_Report`: polymorph and #run statistics | all | |
| `Autorun.jai` | `+Autorun`: run the program after a successful build | all | |
| `Icon.jai` | `+Icon -icon file.ico`: set the executable icon | all | **Windows only** in practice: logs an error on other OSes. |
| `MacOS_Bundler.jai` | `create_app_bundle(name, exe, icon, resources_dir, ...)` | all | writes `Name.app/Contents/{MacOS,Resources,Info.plist}`; the plist it writes was an empty `<dict>` in our test: fill it yourself. |
| `Project_Generator.jai` | Generate Visual Studio solution files | all | Windows-oriented. |
| `linux_build.jai` | Plugin to build Linux binaries **from Windows** with an Unreal cross toolchain | none (asserts Windows) | |
| `executable_formats` | Parse COFF/PE, ELF, Mach-O, ar archives, universal binaries, `.tbd` | all | used by `examples/dump_binary_file.jai`. |
| `debug_info` | Parse DWARF, CodeView, PDB | all | |
| `Remap_Context.jai` | Copy a caller's Context into a DLL's differently laid-out Context | all | `VERBOSE := true` default prints every member: import with `(VERBOSE = false)`. |
| `Protocol_For_Memory_Visualization.jai` | Wire format of the memory-debugger visualizer | all | internal. |
| `Overwriting_Allocator`, `Unmapping_Allocator`, `rpmalloc`, `Thread`, `Memory`, `Default_Allocator` | Allocators, threads, memcpy variants | all (`Memory` loads its x64 code only `#if CPU == .X64`) | jai-systems. |

---

## Patterns seen across the bundle

- **Generated bindings** ship with their generator: `stb_image/generate.jai`, `freetype/generate.jai`,
  `lz4/generate.jai`, `Curl`, `ImGui`, `SDL`, `Socket`, `POSIX`, `Vulkan`, `d3d*`, `Android`, `Objective_C`.
  They compile the C library (BuildCpp) when given `- -compile`, then call `generate_bindings`; libraries live in
  per-OS folders (`macos/`, `linux/`, `windows/`, `android/arm64/`) selected with `#if OS == ...` around
  `#library` declarations. Copy this layout for your own bindings modules.
- **Per-OS files**: `module.jai` does `#if OS == { case .WINDOWS; #load "windows.jai"; ... }`
  (File, Process, Input, Window_Creation, Basic).
- **Module parameters** appear where a module has build-time options: `Basic` (program parameters), `Hash_Table`
  (`COUNT_COLLISIONS`), `Thread`, `Simp` (`render_api`), `Iprof`, `Codex`, `Curl`, `Remap_Context`, `Debug`,
  `Input`, `Window_Creation` (`DEFAULT_MSAA`), `Float16`, `Deep_Copy`, `Flat_Pool`, `rpmalloc`.
- **x86_64-only native libraries on Apple Silicon**: `MojoShader/mac`, `meshoptimizer/macos` (and the VR example's
  `libvma.dylib`) fail to load on arm64 Macs. `lz4`, `stb_*`, `freetype`, `Curl` ship universal binaries.
