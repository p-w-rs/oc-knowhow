# C and C++ interop (beta 0.2.032)

Checked on macOS arm64 (Apple clang 21, Xcode `ld`), powerslabs (Arch, gcc 16, clang) and ubuntu-laptop (Ubuntu,
gcc 15, **no clang**). Examples 29–36 in `examples/jai/jai-modules/` pass on all three. Bundle references:
`how_to/011_context.jai` (#c_call and push_context), `how_to/095_static_if.jai` (per-OS foreign calls),
`how_to/400_workspaces.jai` (#program_export), `examples/dll`, `examples/output_types`, `examples/ios_library`,
`modules/Bindings_Generator/examples` (C++), every `modules/*/generate.jai`.

## 1. Declaring C functions and data

```jai
geo  :: #library "lib/geo";                 // lib/geo.dylib|.so|.dll (+ .a|.lib), relative to THIS file
libc :: #library,system "libc";             // searched in system paths
geo_add   :: (a: s32, b: s32) -> s32 #foreign geo;                 // C symbol = Jai name
c_strlen  :: (s: *u8) -> u64 #foreign libc "strlen";               // C symbol given explicitly
c_printf  :: (fmt: *u8, args: ..Any) -> s32 #foreign libc "printf"; // C varargs
geo_calls: s32 #elsewhere geo;                                     // a C global variable
Callback  :: #type (acc: s32, value: s32, user: *void) -> s32 #c_call;
```

| Directive | Meaning |
|---|---|
| `#foreign lib ["sym"]` | A C-convention procedure implemented in `lib` (short for `#c_call #elsewhere`). |
| `#elsewhere lib ["sym"]` | Defined in another library with **Jai** convention (Jai DLLs), or data (`x: T #elsewhere lib;`). |
| `#c_call` | C calling convention, no implicit `context`. Required for callbacks handed to C. |
| `#no_context` | Jai convention without the hidden context parameter (since 0.0.075). |
| `#program_export ["name"]` | Export a procedure (or data) under its plain name from your executable/library. |
| `#library "path"` | A user library; path without extension, relative to the declaring file. |
| `#library,system "name"` | A system library (`libc`, `libm`, `user32`, `Cocoa` framework, ...). `#system_library` is an older spelling, still accepted silently. |
| `,no_dll` | Only a static library exists (`.a`/`.lib`). |
| `,no_static_library` | Only a dynamic library exists; needed on Windows when using `#elsewhere` data. |
| `,link_always` | Keep it on the link line even if no declaration referencing it is used (unused libraries are culled since 0.1.084). |
| `#cpp_method`, `#cpp_return_type_is_non_pod` | C++ member-function ABI (implicit `this`) and non-POD return convention; Bindings_Generator emits them. |

Old code: `#foreign_library "x"` / `#foreign_system_library "x"` were renamed in 0.1.049 and removed in 0.2.002:
*"Invalid toplevel directive name 'foreign_system_library'"* [38].

## 2. How `#library` is resolved

- **At compile time the compiler loads the library** (dlopen/LoadLibrary) and looks up every `#foreign` symbol
  of declarations it compiles. Consequences, all observed:
  - `#library "lib/geo"` with only `lib/geo.a` present fails: *"lib/geo.dylib: Dynamic library load failed"*.
    Use `#library,no_dll` [29]; then a misspelled symbol is reported by the **linker** (`Undefined symbols ...
    _geo_add_intz`) instead of at compile time.
  - A library built for another CPU fails to load (the bundled MojoShader and meshoptimizer `.dylib`s are
    x86_64-only, so those modules don't compile on Apple Silicon); a `.so` whose own dependencies are missing
    fails too (bundled `libcurl.so` needs `libssl.so.1.1`).
  - `#run` can call into the library at compile time [30].
  - `Build_Options.lazy_foreign_function_lookups = true` skips the compile-time load (the Android build uses it);
    the program still links against the library, so a missing library then fails at the link step instead.
- File names tried for `#library "x"`: macOS `x.dylib` / `x.a`, Linux `x.so` / `x.a`, Windows `x.dll` + `x.lib`.
  When **both** a static and a dynamic library exist, the static one was linked (macOS, even with
  `,no_static_library`; look at the link line).
- `#library,system` on Linux searches the paths from `/etc/ld.so.conf` (0.1.087) and links with `-l<name>`, so it
  needs the **development symlink** (`libGL.so`, `libcurl.so`): Ubuntu without `-dev` packages fails with
  *"lld-linux: error: unable to find library -lGL"* even though `libGL.so.1` exists. A full name like
  `"libatomic.so.1"` is accepted on Linux. On macOS, frameworks are system libraries (`#library,system "Cocoa"`).
- See the link line: `Build_Options.text_output_flags = .OUTPUT_LINK_LINE` (default on unless `-quiet`), or the
  `Running linker:` line. Linux links with the bundled `lld-linux`; macOS with Xcode's `ld` again since 0.2.031.

## 3. Finding shared libraries at run time

| OS | What Jai executables contain | What to do |
|---|---|---|
| macOS | `LC_RPATH @loader_path` | Give the dylib an install name `@rpath/<relative path>` (BuildCpp does: `-install_name @rpath/lib/x.dylib`) and ship it at that path next to the executable. A dylib without `@rpath` name is found only where it was built. |
| Linux | `RUNPATH $ORIGIN` | A `.so` **without SONAME** is recorded by its absolute build path (works until moved). With `-Wl,-soname,libx.so` the NEEDED entry is `libx.so` and is found next to the executable. Library in a subfolder: add `additional_linker_arguments = .["-rpath='$ORIGIN/lib'"]` [36]. |

The Linux link command goes through a shell: an unquoted `"$ORIGIN/lib"` argument was expanded to `/lib`
(RUNPATH `[$ORIGIN:/lib]`); keep the single quotes inside the argument as above.

Curl as a real case: on the Mac the program builds but dies with dyld *"Library not loaded: @rpath/libcurl.dylib"*
until `modules/Curl/macos/lib/libcurl.dylib` is copied next to the executable; on Linux use
`#import "Curl"()(LINUX_USE_SYSTEM_LIBRARY = true)` (worked on Arch; needs the `libcurl.so` symlink).

## 4. Types and values across the boundary

| C | Jai |
|---|---|
| `int8_t … int64_t`, `uint8_t … uint64_t` | `s8 … s64`, `u8 … u64` (`int` in Jai is 64-bit: never use it for C `int`) |
| `int`, `unsigned`, `long` (LP64) | `s32`, `u32`, `s64` (Windows `long` is 32-bit) |
| `size_t`, `ptrdiff_t` | `u64`, `s64` on 64-bit targets |
| `float`, `double` | `float32` (`float`), `float64` |
| `bool` (C99/C23) | `bool` (1 byte) |
| `T *`, `void *`, `const char *` | `*T`, `*void`, `*u8` |
| `T (*f)(…)` | `#type (…) -> T #c_call` |
| `struct` | Jai struct with the same members in the same order (same natural alignment) |
| `__attribute__((packed))` | members with `#align 1` (what Bindings_Generator emits) — **not** `#no_padding` |
| `enum` | `enum s32`/`u32` or the matching integer |
| `T arr[N]` parameter | `*T` or `*[N] T` (fixed arrays cannot be passed by value: compile error) |

- **Strings**: a Jai `string` is `{count, data}` without a terminator. String **literals** convert to `*u8`
  (their data ends in 0); computed strings do not: *"Dynamically-computed strings do not cast to *u8; only
  literals do."* [31]. Use `temp_c_string(s)` (temporary storage) or `to_c_string(s)` (heap, free it). Back:
  `to_string(c_ptr)` borrows (strlen, no copy); `to_string(ptr, count)` for counted data; `copy_string` to keep it.
- **Arrays**: pass `arr.data, xx arr.count`. Let C write into memory you own (`buf: [64] u8; f(buf.data, buf.count)`).
- **Structs** by value and by pointer work both ways on the ARM64 (Apple) and SysV x64 ABIs; return of structs too.
  Check layouts: compare `type_info(T).members[i].offset_in_bytes` / `size_of(T)` with C's `offsetof`/`sizeof`
  (there is no `offset_of` builtin) [29]. `#no_padding` only removes trailing padding (u8,s32,u16 → 0,4,8, size 10).
- **Varargs** to C: declare `args: ..Any` on the `#foreign` declaration; ints, floats (promoted correctly) and string
  literals worked with `printf`. Jai `#c_call` procedures cannot *take* varargs (*"#c_call procedures cannot take
  varargs unless they are #foreign or #elsewhere"*).
- **Output ordering**: C's `printf` buffers separately from Jai's `print`. When stdout is a pipe or file, C output
  appeared after later Jai output; call `fflush(null)` (declare it from libc) before printing from Jai again [30].
- Integer literal pitfall in callbacks: a nested `ifx` with literals produced `s64` and failed to return as `s32`
  (*"Loss of information (trying to fit 64 bits into 32 bits)"*); use plain `if`/`return` or cast.

## 5. Callbacks from C into Jai

```jai
max_reducer :: (acc: s32, value: s32, user: *void) -> s32 #c_call {
    calls := cast(*int) user;
    calls.* += 1;
    push_context { print("value %\n", value); }   // print needs a context
    return ifx value > acc then value else acc;
}
```

- Must be `#c_call`: passing a normal procedure fails with *"Type mismatch: the procedure must use the C calling
  convention, but the given procedure is native."* [32].
- No context inside: calling `print` etc. directly fails with *"Cannot call into a native procedure, from a #c_call
  procedure, without using push_context"* [33]. `push_context { }` gives a default context (default allocator,
  logger, temporary storage); to share the caller's allocator, pass state through the `void *user` pointer.
- Globals are fine without a context (example 36 counts callbacks in a global).

## 6. Calling Jai from C: libraries and exports

- Build outputs per workspace: `options.output_type = .EXECUTABLE | .DYNAMIC_LIBRARY | .STATIC_LIBRARY |
  .OBJECT_FILE` (`examples/output_types`). `runtime_support_definitions`: `.AUTO` (default: entry point for
  executables, `ONLY_INIT` otherwise), `.ENTRY_POINT_AND_INIT`, `.ONLY_INIT`, `.OMIT` (when linking several Jai
  libraries into one program).
- Mark exported procedures `#program_export` and usually `#c_call`; inside them `push_context { ... }` before
  calling Jai code that needs a context.
- `modules/generate_c_header.jai` writes a header: create a `Header_Info`, call `handle_message(*info, message)` for
  every message of that workspace's intercept loop, then `generate_header(*info, "x.h")` [34]. It declares the
  exported procedures, the structs they use, typedefs for Jai integer names, and
  `__jai_runtime_init(argc, argv)` / `__jai_runtime_fini(ctx)`.
- C host, checked on all three machines [34]:
  - call `__jai_runtime_init` first (sets up context and temporary storage), `__jai_runtime_fini` at the end;
  - compile with **`-std=c17`**: the header does `typedef s8 bool`, which C23 compilers (gcc 15+ default) reject
    (*"two or more data types in declaration specifiers"*);
  - on Linux link with **`-no-pie`**: Jai objects are not position-independent (*"relocation R_X86_64_32S ...
    can not be used when making a PIE object"*); no extra `-l` flags were needed;
  - on macOS pass `-mmacosx-version-min=<minimum_os_version>` (11.0 by default) to avoid ld's "built for newer
    macOS version" warnings.
- The header and library from one `build.jai`: STATIC_LIBRARY workspace + header generation + `build_cpp_executable`
  for the C host (example 34). For iOS, `examples/ios_library` does the same with `os_target = .IOS`.

## 7. Jai DLLs used by Jai programs (plugins)

- Build the library workspace first and **wait for its COMPLETE message**: the program's compile loads the library
  (examples/dll, [35]).
- Program side: `plugin :: #library,no_static_library "plugin";`, procedures declared `#elsewhere plugin` (Jai
  convention) or `#no_context #elsewhere plugin`.
- The two sides can have different `#Context` layouts (different modules, `#add_context` fields). Library
  procedures that use the context call `Remap_Context()` first (module `Remap_Context`, import it with
  `(VERBOSE = false)` or it logs every copied member); it copies members with the same name and size.
- Run time: found next to the executable (rpath rules of §3).

## 8. Compiling C/C++ from the metaprogram: BuildCpp

```jai
#import "BuildCpp";
build_cpp_static_lib("lib/geo", "csrc/geo.c", extra = .["-fPIC"], compiler_executable_path = "cc");
build_cpp_dynamic_lib("libgreet", "csrc/greet.c", extra = .["-Wl,-soname,libgreet.so"]);
build_cpp_executable("host", "host.c", extra = .["-std=c17"], library_files = .["stats.a"]);
```

- Signature: `build_cpp(output_basename, files: ..string, type, debug := false, extra := [], library_files := [],
  target := OS, compiler_executable_path := "", ar_executable_path := "", working_directory := "")`, plus the
  `build_cpp_static_lib/dynamic_lib/executable` shorthands and `build_universal_macos_binary` (x64 + arm64 + lipo).
  Returns false and reports through `compiler_report` on failure; it can only run at compile time.
- Compiler choice on Unix: `compiler_executable_path`, else `$CC` / `$CXX` (C++ when any file ends in `.cpp`), else
  `clang` / `clang++`. **On a Linux box without clang (ubuntu-laptop) the default fails**: pass
  `compiler_executable_path = "cc"` or set `CC`/`CXX` (the bundled C++ example built with `CXX=g++`).
- It adds `-O3` (or `-g -Og` with `debug`), `-shared -fpic` for dynamic libraries, on macOS
  `-install_name @rpath/<output>` for dylibs and `-rpath @loader_path` for executables, then `ar -rc` for static
  libraries (deleting the old archive first). Add `-fPIC` yourself for static libraries that end up in shared ones.
- Windows: finds Visual Studio and the Windows SDK and runs `cl.exe`/`lib.exe` (not tested here).

## 9. C++

- C++ classes are reachable through Bindings_Generator: it emits structs with `vtable` pointers, methods as
  `#cpp_method #foreign lib "<mangled name>"`, `Constructor`/`Destructor` members, and `#cpp_return_type_is_non_pod`
  where needed. The bundled `modules/Bindings_Generator/examples/first.jai` (compile a C++ library, generate, call
  constructors, virtual methods, destructors) ran on macOS and on Linux with `CXX=g++`.
- Inline-only C++ functions (constructors defined in the header) have no symbol in the library: the example strips
  them with `strip_flags = .INLINED_FUNCTIONS` on Unix.
- Name mangling differs per platform: generate bindings per OS (`macos.jai`, `linux.jai`, `windows.jai`) and `#load`
  the right one with `#if OS`.
- For anything big, prefer a C wrapper layer (`extern "C"`) and bind that.

## 10. Checklist when a binding does not work

1. Compile error "Dynamic library load failed": library missing, wrong path (relative to the declaring file), wrong
   CPU, or its dependencies missing → `otool -L` / `ldd`; static-only → `,no_dll`.
2. "Unable to resolve foreign symbol 'x' inside library 'y'": wrong name, C++ mangling, or a macro instead of a
   function.
3. Link errors: look at the link line (`Running linker:`); `-lfoo` not found on Linux → missing `libfoo.so` symlink.
4. Wrong values: compare struct layouts (C `offsetof` vs `type_info`), integer widths (C `int` = `s32`), enums,
   packed structs (`#align 1`), and by-value vs by-pointer.
5. Crashes in callbacks: missing `#c_call`, or Jai code used without `push_context`.
6. Run time "Library not loaded" / "cannot open shared object file": rpath/SONAME (§3).
