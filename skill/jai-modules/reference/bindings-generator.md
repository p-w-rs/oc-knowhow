# Bindings_Generator: Jai bindings from C/C++ headers (beta 0.2.032)

`modules/Bindings_Generator` parses headers with the **libclang 21 it ships** (`Bindings_Generator/bin/libclang.*`
for macOS, Linux, Windows): nothing to install. It writes a `.jai` file of declarations; you commit that file and
regenerate when the header changes. Example 36 does the whole loop and passes on macOS arm64, Arch and Ubuntu.
Read `modules/Bindings_Generator/module.jai` (`Generate_Bindings_Options`, ~150 commented fields) and the
`generate.jai` of bundled bindings (`stb_image`, `lz4`, `freetype`, `Socket`, `POSIX`, `ImGui`, `d3d11`, `Android`)
for real configurations: `library_search query="Generate_Bindings_Options" sources=["jai-modules-src"]`.

## 1. Minimal generator

```jai
#import "Basic";
#import "Compiler";
#import "Bindings_Generator";

#run {
    set_build_options_dc(.{do_output = false});
    options: Generate_Bindings_Options;
    array_add(*options.library_search_paths, "lib");
    array_add(*options.libraries, .{filename = "shapes"});     // lib/shapes.dylib|.so|.dll must exist
    array_add(*options.source_files, "csrc/shapes.h");
    array_add(*options.strip_prefixes, "shapes_");
    if !generate_bindings(options, "shapes_bindings.jai")  compiler_set_workspace_status(.FAILED);
}
```

- `generate_bindings(options, output_file) -> bool` (also a variant returning the `String_Builder`). Took 0.3–0.7 s.
- The library must exist when generating: the generator loads it to check that each function is really exported
  (missing → *"Could not load library: 'x'"*; symbols not found are stripped, see `strip_flags`
  `.SYMBOLS_WITH_UNKNOWN_FOREIGN_LIBS`). Build it first (BuildCpp, as in example 36) or point at an installed one.
- Run as a compile-time script (`jai generate.jai`, the bundled pattern: `AT_COMPILE_TIME :: true;` and a
  `#run,stallable { ... }`), or compile it to an executable that you run.
- Typical field set: `libraries` (`.{filename, identifier}`), `library_search_paths`, `system_libraries` /
  `system_library_search_paths`, `source_files`, `include_paths`, `extra_clang_arguments` (`"-x", "c++"`,
  `"-DFOO"`, `"-target", ...`), `strip_prefixes`, `generate_library_declarations` + `footer`/`header` (write your
  own `#library` lines, e.g. per-OS folders), `generated_library_path_prefix`, `visitor_with_data` (edit or omit
  declarations), `log_stripped_declarations`, `strip_flags`, `generate_compile_time_struct_checks`,
  `try_to_preserve_comments`, `move_struct_functions_to_global_scope`. Deprecated: `visitor`,
  `libnames`/`libpaths`.

## 2. What the output looks like (checked)

From a small header with a `#define`, an enum, plain and packed structs, a function-pointer typedef, functions and an
`extern` global:

- `#define SHAPES_MAX_POINTS 64` → `SHAPES_MAX_POINTS :: 64;` (macros keep their names; `strip_prefixes` does not
  apply to them).
- `typedef enum { SHAPE_CIRCLE = 1, ... } Shape_Kind;` → `Shape_Kind :: enum u32 { CIRCLE :: 1; ... }` plus aliases
  with the original names (`SHAPE_CIRCLE :: CIRCLE;`; turn off with `alias_original_enum_names = false`). Enum value
  prefixes are auto-detected and stripped.
- Structs → Jai structs; a packed struct → members with `#align 1`. A `#run` block asserts every member offset and
  struct size at compile time (`generate_compile_time_struct_checks`), so a layout mismatch is a compile error.
- Function-pointer typedef → `#type (...) -> T #c_call`.
- Functions → `area :: (kind: Shape_Kind, size: float) -> float #foreign shapes "shapes_area";`: `strip_prefixes`
  renames the Jai side, the C symbol stays in quotes.
- `extern int32_t shapes_calls;` → `calls: s32 #elsewhere shapes "shapes_calls";`.
- C comments next to declarations are copied.
- The library declaration ends up in `#scope_file` at the bottom: `shapes :: #library "lib/shapes";` (path from
  `library_search_paths`; `"./shapes"` when none was given). `#import "Basic"` is added for the asserts.
- Use the result with `S :: #import,file "shapes_bindings.jai";` or `#load` it from your module's `module.jai`.

## 3. Pitfalls found

- **`strip_prefixes` also renames types**: `shapes_kind` became `kind`, and the parameter `kind: kind` then failed
  with *"Attempt to use a value inside its own declaration"*. Choose prefixes so stripped type names stay distinct
  (or fix names in a visitor).
- Headers in system directories (`/usr/include`, SDK paths) are **ignored** by default ("N system declarations
  were ignored"): for system libraries add `path_fragments_to_treat_as_non_system_paths` / `system_types_to_include`
  (the module header warns about this; POSIX and jai-on-linux do it).
- Functions taking `va_list` are stripped by default; printf-style varargs functions get wrappers
  (`generate_printf_wrappers`).
- Generated code targets the OS/CPU you run on (`options.os`, `options.cpu` are experimental for others; pass a
  `-target` to clang). Bundled bindings keep one generated file per OS or `#if OS` blocks around library paths.
- C++: needs `extra_clang_arguments = .["-x", "c++"]`; mangled names differ by platform, so generate per OS. Methods
  come out as `#cpp_method`, with `Constructor`/`Destructor` and vtable structs; inline-only functions have no
  symbol (`strip_flags = .INLINED_FUNCTIONS`). The bundled example (`modules/Bindings_Generator/examples/first.jai`)
  ran on macOS and on Linux with `CXX=g++` (BuildCpp's default `clang++` is absent on some Linux machines).
- Re-running is cheap; keep `generate.jai` in the repository next to the generated file and note the header version
  it was generated from.

## 4. How the bundled modules do it (pattern to copy)

`modules/stb_image/generate.jai` (and lz4, stb_*): command-line flags after `-` (`- -compile`, `-debug`, `-x64`,
`-arm64`, `-android`) choose whether to compile the C source with BuildCpp (universal binary on macOS, `-fPIC` on
Linux) into per-OS folders (`macos/`, `linux/`, `windows/`, `android/arm64/`), then generate `bindings.jai` with
`generate_library_declarations = false` and a `footer` containing `#if OS == ... #library "<os>/name"` blocks.
`module.jai` just `#load`s `bindings.jai` and adds what the generator cannot know (extra system libraries with
`,link_always`, type aliases such as `FILE :: void` on Windows).

Related community material: `jai-on-linux-source` (generated X11/xcb/Wayland/xkb bindings with system-path settings).
