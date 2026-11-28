# Platforms, per-OS code and cross-compiling (beta 0.2.032)

Hosts used: macOS arm64 (`jai-macos`, a universal binary), Arch Linux x64 and Ubuntu 26.10 x64 (`jai-linux`).
No Windows or Linux ARM64 machine was available: statements about them are from building objects only or from the
bundle's documentation. Bundle references: `how_to/095_static_if.jai`, `how_to/950_cross-compiling/`,
`examples/wasm`, `examples/ios_library`, `modules/Android/README.txt`, `README.txt` (requirements).

## 1. Compile-time platform constants

- `OS` (`Operating_System_Tag`: `.WINDOWS .LINUX .MACOS .ANDROID .IOS .WASM .PS5 .NN_SWITCH .NN_SWITCH2 .XBOX`, see
  `modules/Preload.jai`), `CPU` (`.X64 .ARM64 .CUSTOM`), `OS_IS_UNIX` (macOS, Linux, iOS, Android, PS5; defined in
  Runtime_Support), `IS_CROSS_COMPILING` (since 0.1.084). They describe the **target** of the workspace being
  compiled, including inside `#run` (§4).
- Static branching (untaken branches are not compiled, so they may reference APIs that do not exist):

```jai
#if OS == {
    case .WINDOWS; #load "platform/windows.jai";
    case .MACOS;   #load "platform/macos.jai";
    case .LINUX;   #load "platform/linux.jai";
    case;          #assert false "unsupported OS";
}
#if CPU == .X64 { #import "Machine_X64"; }      // x64-only module
x := #ifx OS == .WINDOWS then "\\" else "/";    // #ifx needs both branches
```

  `#if x == { case ...; }` exists since 0.1.084; older code chains `#if ... else #if ...` [37].
- Bundled modules use the same pattern: `module.jai` loads `windows.jai`/`unix.jai`/... (File, Process, Input,
  Window_Creation, Basic) and declares per-OS `#library` paths in `#if OS` blocks.
- Library declarations per OS and CPU:

```jai
#if OS == .WINDOWS      mylib :: #library "windows/mylib";
else #if OS == .MACOS   mylib :: #library "macos/mylib";      // universal binary, or split by CPU:
else #if OS == .LINUX   mylib :: #library "linux/mylib";
```

  Apple Silicon is the default macOS target (since 0.1.090); x86_64-only dylibs cannot be loaded by the arm64
  compiler (MojoShader, meshoptimizer in the bundle). Ship universal binaries (`BuildCpp.build_universal_macos_binary`)
  or `#if CPU ==` separate paths.
- CPU features at run time: `#import "Machine_X64"` (x64 only): `info := get_cpu_info();`
  `check_feature(info.feature_leaves, .AVX2)` (true on powerslabs).
  `System.get_number_of_processors(.PERFORMANCE_LOGICAL | .ALL_LOGICAL | ...)`. x64 `#asm` does not exist on
  ARM64 targets and cannot even run at compile time on the ARM compiler (how_to/900 fails on the Mac): guard all
  `#asm` with `#if CPU == .X64`.

## 2. What each host needs

- **macOS**: Xcode (the compiler links with the system `ld` via `xcrun` since 0.2.031; the README notes that the
  command-line tools alone may lack pieces). Output: executable + `.dSYM`. `minimum_os_version` defaults to 11.0;
  pass the same `-mmacosx-version-min` to C code you build, or ld warns.
- **Linux**: the compiler binaries need a reasonably recent glibc (built on Ubuntu 20.04 since 0.2.027–0.2.029);
  links with the bundled `lld-linux`. System libraries are found through `/etc/ld.so.conf`; `-l<name>` needs the
  development symlink (`libGL.so`, `libcurl.so`): on Ubuntu without `-dev` packages GL, Simp, GetRect failed to
  link. A full file name works without the symlink: `#library,system "libm.so.6"` (checked on both machines).
- **Windows** (not tested here): per the README, install a Windows SDK and a Visual C++ redistributable (installers
  in `~/jai/current/redist/`, `winsdksetup.exe` needs internet). BuildCpp locates Visual Studio for C/C++.
- C/C++ compiler for BuildCpp/Bindings examples: `cc` everywhere; `clang` is BuildCpp's default and is missing on
  some Linux boxes (pass `compiler_executable_path = "cc"` or set `CC`/`CXX`).

## 3. Cross-compiling: what works (checked)

A workspace becomes cross-compiling when `os_target`/`cpu_target` differ from the host:

```jai
w := compiler_create_workspace("linux x64");
options := get_build_options(w);
copy_commonly_propagated_fields(get_build_options(), *options);
options.os_target  = .LINUX;
options.cpu_target = .X64;
options.output_type = .OBJECT_FILE;                          // link on the target
options.runtime_support_definitions = .ENTRY_POINT_AND_INIT; // object gets main + runtime start-up
set_build_options(options, w);
add_build_file("app.jai", w);
```

| Host → target | Output | Result |
|---|---|---|
| macOS arm64 → Linux x64 | OBJECT_FILE | ELF x86-64 `.o` in 0.15 s; on Linux `cc -no-pie -o app app.o` → runs, prints `cross-compiled: true` (plain `cc` fails: the object is not PIE). |
| macOS arm64 → Linux x64 | EXECUTABLE | **fails at link**: the compiler runs its bundled lld in Darwin mode (*"lld-macos: error: malformed platform: 11.0.0"*). |
| macOS arm64 → macOS x64 | EXECUTABLE | works (`arch -x86_64 ./app` runs it). |
| macOS or Linux → Windows x64 | OBJECT_FILE | COFF x64 `.obj` (not linked: no Windows machine). |
| any → iOS arm64 | STATIC_LIBRARY | `.a` produced on macOS (examples/ios_library also writes a C header with generate_c_header; the Xcode app is built in Xcode). |
| any → Linux **ARM64** | OBJECT_FILE | **pitfall**: `cpu_target = .ARM64` alone produced an **x86-64** ELF object (on all three hosts). Set `options.llvm_options.target_system_triple = "aarch64-unknown-linux-gnu"` to get an aarch64 object (not linked or run: no ARM64 Linux machine). |
| Linux x64 → Linux x64 | OBJECT_FILE | `cc -no-pie` links it (`cross-compiled: false`). |

Example 37 builds the Windows, Linux x64 and Linux ARM64 (with and without triple) objects from one `build.jai`
and checks each object's machine field on every host. For linking a Linux executable you need the target's C
runtime and libraries; the practical routes are: build on the target, or build objects here and link there (Docker
`--platform linux/amd64` with gcc is what how_to/950 suggests).

## 4. Compile-time code while cross-compiling

- A normal `#run` in a cross-compiling workspace runs the **target's** bytecode on the host: `OS`/`CPU` have the
  target values, struct layouts are the target's. The context's allocator, logger and temporary storage are swapped
  for host versions, so allocation works, but **file I/O, syscalls and `#foreign` calls into target libraries do
  not**, and x64 `#asm` cannot run on an ARM host (how_to/950).
- `#run,host -> T { ... }` (0.2.030) compiles and runs the block in a hidden host workspace: it sees host `OS`/`CPU`
  and must `#import` what it needs inside the block; it can return only primitive types, strings and arrays of them,
  and takes no arguments. Use it for reading files at compile time when cross-compiling. Checked: from the Mac, a
  Linux object printed `built on MACOS/ARM64` from a `#run,host` string.
- `#foreign`/`#elsewhere` procedures without a library identifier (allowed since 0.1.077) describe symbols that
  exist only at run time (WASM imports, libraries absent on the host). `lazy_foreign_function_lookups = true`
  stops the compiler from loading `#library` files (Android builds use it); the linker still needs them.

## 5. WebAssembly (examples/wasm)

- Target `os_target = .WASM`, `cpu_target = .CUSTOM`, LLVM backend, **wasm64 only** (needs the Memory64 feature),
  `llvm_options.target_system_features = "+bulk-memory"`, `enable_split_modules = false`,
  `function_sections = true`, `backtrace_on_crash = .OFF`, the bundled `lld` (used for WASM even on macOS).
  The example replaces the default allocator with a prebuilt `walloc.o` through
  `remap_import(w, "*", "Default_Allocator", "Walloc")` and declares JavaScript imports as `#foreign` procedures
  without a library (`wasm_write_string`, `wasm_debug_break`, ...).
- Checked (copy in scratch): builds `public/main.wasm` (~260 KB) in 0.23 s on macOS; **Node 24** instantiated it
  with a small loader (Memory64 works there) and ran `main(0, 0n)`. With the example's 24 KB stack
  (`-z stack-size=`) it trapped *"memory access out of bounds"* while printing type info; with a 1 MB stack it ran to
  completion. Browsers need Memory64 support (check the WebAssembly roadmap for your browser).

## 6. Android and iOS

- Android: `modules/Android` (NDK bindings, `Android/Toolchain`, `Native_App`, examples). Needs the Android SDK,
  NDK and Java (Android Studio installs them; `modules/Android/README.txt` asks for `ANDROID_HOME`,
  `ANDROID_NDK_HOME`, `JAVA_HOME`) and a device or emulator; builds a
  `DYNAMIC_LIBRARY` per ABI (arm64, x64) with `lazy_foreign_function_lookups` and a custom link step, then packages
  an APK. Not run here (no SDK). Import submodules as `#import "Android/EGL"`.
- iOS: `examples/ios_library` builds a static library (`os_target = .IOS`, `cpu_target` ARM64 or X64 for the
  simulator) plus a C header, used from an Xcode project; `modules/iOS/Toolchain.jai` finds SDK paths through
  `xcrun` (`#import "iOS/Toolchain"`; there is no plain `iOS` module).

## 7. Packaging helpers

- `MacOS_Bundler.create_app_bundle(app_name, exe_path, icon_path, resources_dir, only_copy_subdirectories_and_files,
  write_plist)` → `Name.app/Contents/{MacOS/Name, Resources/..., Info.plist}`. Checked: the executable runs from the
  bundle, but the generated `Info.plist` contained an empty dictionary: write your own keys
  (`CFBundleExecutable`, `CFBundleIdentifier`, ...) before shipping. focus (`focus-editor-source`) builds an
  `.app` and `.dmg` from its metaprogram.
- `+Icon -icon file.ico` (Icon plugin) and `Windows_Resources` (`set_icon_by_filename`, manifests) only work for
  Windows executables; on other OSes the plugin logs an error. `Ico_File` creates `.ico` files (Windows modules).
- `Project_Generator` writes Visual Studio solutions; `linux_build.jai` is a plugin for building Linux binaries
  *from Windows* with an external clang toolchain.

## 8. Output types (all targets)

`Build_Options.output_type`: `.EXECUTABLE`, `.DYNAMIC_LIBRARY` (`.dylib`/`.so`/`.dll`), `.STATIC_LIBRARY`
(`.a`/`.lib`), `.OBJECT_FILE` (`.o`/`.obj`), `.NO_OUTPUT`. `output_executable_name` (no extension; extensions are
added unless `append_executable_filename_extension = false`), `output_path`, `intermediate_path` (`.build/`).
`runtime_support_definitions` decides whether the entry point and runtime init are included (§3, c-interop §6).
`examples/output_types/build.jai` builds all four from one metaprogram and prints each link line.
