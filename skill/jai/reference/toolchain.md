# Jai toolchain: installing, building, flags, output, errors, navigating (beta 0.2.032)

Verified on macOS arm64 (`jai-macos`) and Linux x86-64 (`jai-linux`, Obarun and Ubuntu 26.10). The command line is
implemented by `~/jai/current/modules/Default_Metaprogram.jai`: read it when a flag behaves unexpectedly.

## 1. Installing a beta

- The beta is a folder, no installer: unpack it to `~/jai/beta-0.2.032` and point a symlink `~/jai/current` at it, so
  scripts and skills can say `~/jai/current/bin/jai-macos` (or `jai-linux`) and a new beta is one `ln -sfn` away.
  Keep the previous beta folder until your code builds with the new one.
- Contents: `bin/` (`jai-macos` universal binary, `jai-linux`, `jai.exe`, bundled `lld-*`), `how_to/`, `modules/`,
  `examples/`, `CHANGELOG.txt`, `README.txt`, `editor_support/` (natvis), `redist/` (Windows SDK installers).
- **macOS**: files downloaded with a browser carry the quarantine attribute and trigger Gatekeeper prompts for the
  compiler and the libraries it loads. Clear it once for the whole folder: `xattr -dr com.apple.quarantine
  ~/jai/beta-0.2.032` (the bundle's `macos_de-quarantine.sh` does the same). Linking uses the Xcode toolchain's
  `ld` (found with `xcrun`, since 0.2.031); every build also runs `dsymutil` and writes `name.dSYM`. Install Xcode
  (the README notes that some programs need its libraries). The default target is arm64; the `-x64` backend cannot
  target it.
- **Linux**: x86-64 binaries only, linked with the bundled `lld-linux` against the system glibc (`/lib64/libc.so`,
  `crt1.o`, `ld-linux-x86-64.so.2`). The README says "built on Ubuntu 18.04"; since 0.2.029 the compiler is built on
  Ubuntu 20.04, so it needs at least that glibc (fine on glibc 2.44). System libraries are found through
  `/etc/ld.so.conf`; install `-dev` packages for libraries you bind to. No Linux arm64 build.
- Put `bin` on PATH if you like; tools that look for `jai-macos`/`jai-linux` on PATH (Jails) otherwise need the root
  passed explicitly.

## 2. Check the version

- `jai -version` and `jai -help` print **only to a terminal**: through a pipe or a file they print nothing (exit 0).
  - macOS: `script -q /dev/null ~/jai/current/bin/jai-macos -version`
  - Linux: `script -qc "~/jai/current/bin/jai-linux -version" /dev/null`
  - Output: `Version: beta 0.2.032, built on 26 November 2026.`
- Pipe-safe alternative (works in CI logs and from agents): `ver.jai` containing
  `#import "Basic"; #import "Compiler";` and
  `#run { print("%\n", compiler_get_version_info(null)); set_build_options_dc(.{do_output = false}); }`, then
  `jai -quiet ver.jai` prints `beta 0.2.032, built on 26 November 2026` and writes no executable.
- The first line of `CHANGELOG.txt` also names the version.

## 3. Building

- `jai file.jai` compiles the default metaprogram, which: changes the working directory to the folder of the first
  file; sets the output name to the first file's name without `.jai` and the output path to its folder; imports the
  Check plugin; compiles; links. Objects go to `.build/` next to the source (`name_0_w2.o … name_3_w2.o` with LLVM's
  4 split modules in debug builds; one `name.o` with `-x64`; `w2` is the workspace number).
- Success output: a `Running linker: …` line (and on macOS `Running dsymutil: …`), then
  `Stats for Workspace 2 ("Target Program"):` with lexer line counts and front-end / backend / link times. A hello
  world: about 10 800 lines (Basic and friends) in 0.13–0.15 s. `-quiet` prints nothing at all on success.
- Compile errors go to **stderr** (stdout stays empty), exit code 1:
  ```
  In Workspace 2 ("Target Program"):
  /abs/path/err.jai:1,24: Error: Type mismatch. Type wanted: s64; type given: string.

      main :: () { x : int = "nope"; }
                             ^^^^^^
  ```
  Often followed by `Info:` lines and `... in declaration of 'x' (declared type: …)`. `-msvc_format` changes the
  location to `path(1,24): Error:`; colors only appear on a terminal (`-no_color` turns them off). Errors found by
  the Check plugin are labelled `In Workspace 1 ("First Workspace")`. A single program stops at its first error.
- Runtime errors (bounds, casts, asserts, crashes) also go to stderr; see section 7.

## 4. Command-line options (all verified on 0.2.032)

Form: `jai [options] file.jai [more files] [options] [+Plugin plugin-args …] [- metaprogram args …]`. Options may
come before or after the file.

| option | effect (verified) |
|---|---|
| `-quiet` | no linker line, no stats; errors still print |
| `-o`, `-optimized` | LLVM -O3 with SLP/loop vectorization, no split modules, **runtime checks off, stack traces off**. (`-help` writes `-optimzed`; that spelling is rejected) |
| `-od`, `-optimized_debug` | LLVM -O2, runtime checks off, stack traces kept |
| `-very_debug` | VERY_DEBUG: same checks as the default debug build in 0.2.032 (overflow checking stays off) |
| `-release`, `-release_debug` | still work, with `*** Warning: -release will go away, …` (use `-o` / `-od`) |
| `-x64` | in-house backend: x86-64 only (Linux). On Apple Silicon: `Error: The x64 backend supports only x64 CPUs but the CPU target was set to ARM64 (4)` |
| `-llvm` | LLVM backend (already the default) |
| `-exe name` | output name (`-exe named` → `./named`, objects `named_*_w2.o`) |
| `-output_path dir` | output folder, relative to the source file's folder, must exist (otherwise the linker fails: `ld: open() failed, errno=2 …`); absolute paths work |
| `-import_dir dir` | extra module folder (repeatable), relative to the first file's folder; searched before the default ones |
| `-add "code"` | adds code to the program (`-add 'X :: 42'`; stored in `.build/.added_strings_w2.jai`) |
| `-run 'code'` | runs `#run code;` during the build (`-run 'write_string("hi\n")'`); without a source file the build then fails with `Build_Options.output_type is set to EXECUTABLE, but Build_Options.output_executable_name is empty.` |
| `-no_check` | skip the Check plugin: wrong print argument counts become runtime messages (`Invalid % index 2 in the format string …`) |
| `-no_check_bindings` / `-check_bindings` | Check without/with the bindings check (default on) |
| `-no_inline` | disable the bytecode inliner |
| `-no_dce` | keep dead code (e.g. so `+Rewrite` sees it); "temporary option" |
| `-no_split` | one LLVM module instead of four in debug builds |
| `-output_ir` | write `.build/name_N_w2.ll` and `name_N_w2_no_opt.ll` (LLVM IR before/after optimization) |
| `-no_backtrace_on_crash` | no crash handler (smaller executable: 318 KB vs 338 KB for hello world on macOS) |
| `-natvis` | debugger-friendly type names (`array<T>` instead of `[] T`) |
| `-debug_for` | let the debugger step into for_expansion macros |
| `-debugger` | interactive bytecode debugger when compile-time code crashes |
| `-context_size n` | maximum `#Context` size (default 4096; minimum `size_of(Context_Base)` = 96, else an error) |
| `-msvc_format`, `-no_color` | message format and colors |
| `-verbose` | prints the chosen output path/name, the directory change, input files, plugins |
| `-version`, `-help`, `-?` | terminal only (section 2) |
| `- args…` | everything after a lone `-` goes to the metaprogram: `get_build_options().compile_time_command_line` (e.g. `["alpha", "--beta", "3"]`) |
| `+Name args…` | invoke plugin module `Name` with the following arguments up to the next `+`: `+Autorun` (run the program after a successful build; prints `[Autorun] Running: <path>` after the program's output), `+Check` (already on by default), `+Rewrite` / `+Rewrite -write` (section 8). The old `-plug Name` → `Unknown argument '-plug'.` |
| `-- help`, `-- meta M`, `-- import_dir D` | developer options (`jai -- help` lists them: import_dir, meta, no_jobs, randomize, seed, extra, chaos). `jai f.jai -- meta Minimal_Metaprogram` replaces the default metaprogram (no Check plugin then). Anything else after `--` is reserved: `Unknown developer option 'x'. Use '-- help' for help. …` |
| unknown `-x` | `Unknown argument '-x'.` and `Exiting.`, exit 1 |

## 5. Backends and build modes, measured

powerslabs (Linux x86-64), a Collatz search up to 3·10⁶; identical output in every mode:

| flags | codegen | total compile | run time | executable |
|---|---|---|---|---|
| `-x64` | 0.002 s | 0.06 s | 1.25 s | 446 KB |
| default (LLVM, debug) | 0.095 s | 0.15 s | 0.68 s | 544 KB |
| `-od` | 0.52 s | 0.58 s | 0.34 s | 443 KB |
| `-o` | 0.49 s | 0.54 s | 0.34 s | 416 KB |
| `-x64 -o` | 0.002 s | 0.05 s | 1.25 s | 378 KB |

Use `-x64` (Linux) for fast edit-compile loops, the default for debugging, `-o` to ship and to measure speed.
`-o` does not make x64 code faster: it only removes checks and stack traces. Comparing backends is a good probe:
results must match (example 29 runs on Linux only).

## 6. The default metaprogram vs a build file

- Plain `jai main.jai` is enough for most programs: imports, `#load`, a local `modules/` folder and `-import_dir`
  cover project structure (example 25).
- Write a build file when you need settings that have no flag (overflow checks, custom output types, several
  executables, generated code, post-build steps) or a reproducible build command. Minimal shape (example 26):
  `#run { set_build_options_dc(.{do_output = false}); w := compiler_create_workspace("name"); o :=
  get_build_options(w); o.output_executable_name = "name"; /* settings */ set_build_options(o, w);
  add_build_file("main.jai", w); }`. Forgetting `set_build_options_dc(.{do_output = false})` fails with
  `No program entry point was found` (the build file itself would become a program).
- Useful `Build_Options` fields: `output_executable_name`, `output_path`, `intermediate_path`, `output_type`,
  `backend` (`.LLVM`/`.X64`), `arithmetic_overflow_check` (`.OFF`/`.NONFATAL`/`.FATAL`, default OFF),
  `array_bounds_check`, `cast_bounds_check`, `null_pointer_check`, `stack_trace`, `import_path`,
  `emit_debug_info`, `backtrace_on_crash`, `use_ansi_color`, `context_size_max`; `set_optimization(*o, .OPTIMIZED)`
  applies a whole mode. Read `Build_Options` in `modules/Compiler/Compiler.jai`.
- Differences to remember: `-quiet` does not silence workspaces you create; the Check plugin (print argument counts)
  is not attached to them (example 56 shows how to attach it); their automatic `modules/` folder is the one next to
  the build file, not next to the files you add (extend `import_path`, see §9); arguments after `-` are yours.
- Workspaces, the message loop, plugins and code generation are covered by **jai-metaprogramming**.

## 7. Runtime failures: what they look like

| failure | debug build (default, `-very_debug`) | `-od` / `-o` |
|---|---|---|
| array index out of range | `Array bounds check failed. (The attempted index is 11, but the highest valid index is 3). Site is <file>:6.` then `Panic.`, exit 1 | not checked: reads/writes garbage |
| narrowing cast out of range | `Cast bounds check failed.  Number must be in [0, 255]; it was 1100.  Site is <file>:7.` + `Panic.`, exit 1 | not checked: keeps low bits |
| null pointer passed where a value is expected | `Null pointer check failed: Argument 1 is undergoing an automatic dereference, but the pointer is null. Site is …` + `Panic.`, exit 1 | not checked |
| explicit null `p.*` | crash handler: `Program Exception: SEGV_ACCERR` (Mac) / `SEGV_MAPERR … Null Pointer Exception. Attempt to dereference a null pointer.` (Linux), exit 1 | undefined behaviour: seen both as `Breakpoint hit. Stack trace:` (exit 1) and as nothing at all (exit 0) |
| integer overflow | wraps silently (unless a build file sets `arithmetic_overflow_check`; then `Arithmetic overflow. We tried to compute: 2147483647 + 11 …`) | wraps |
| failed `assert` | `<file>:6,56: Assertion failed: <message>`, blank line, `Stack trace:` with `<file>:<line>: <procedure>` lines, exit 1 | same (asserts stay unless `ENABLE_ASSERT=false`) |
| writing into a literal | Mac `SIGBUS: … invalid address alignment`; Linux `SEGV_ACCERR … write to read-only memory`, exit 1 | same |

After `Panic.` debug builds hit a breakpoint: macOS and Linux print `Breakpoint hit. Stack trace:` with native frames.
`-no_backtrace_on_crash` removes the handler.

## 8. Migrating old code with `+Rewrite`

`jai prog.jai -no_dce +Rewrite` reports what it would change (`Plugin Rewrite is being run in read-only mode; …`
and `Rewrite plugin scheduled changes for N file: …`) without touching files; `jai prog.jai -no_dce +Rewrite
-write` rewrites the sources: verified `y := << p;` → `y := p.*;`. Back up first; `-no_dce` makes it see code that
dead-code elimination would skip; macros are only rewritten where invoked. With a custom build file, add the
plugin there. Other old forms must be fixed by hand (see false-friends.md §6–7).

## 9. Navigating Jai code with Jails (jails-query)

- **Jails** is the Jai language server (SogoCZE, MIT; library id `jails-source`). Built for this machine at
  `~/jai/tools/jails/current/jails`. OpenCode V2 accepts an `lsp` config block but does not run language servers, so
  agents use a one-shot shell front end that starts Jails, asks one question and stops it (about 1–2 s per call):
  `pixi exec --spec nodejs=24 node <oc-knowhow>/scripts/jails-query.mjs <command> …` (the skill's live note gives
  the real path of oc-knowhow).
- Commands (verified on example 25's project; output trimmed):
  - `symbols main.jai` → outline: `main  [procedure]  ()  :18` (structs with fields, enums with members, procedures with signatures).
  - `def main.jai print` → `$JAI/modules/Basic/Print.jai:326:1: print :: (format_string: string, args: .. Any, …`
    (definition of the first use of an identifier; `--line N` picks a later use). `def main.jai greet` →
    `modules/Greeter/module.jai:6:1: greet :: (name: string) {`, `def main.jai square` → `util.jai:3:1: …` (follows
    `#import`, local modules and `#load`).
  - `def main.jai:19:5` (1-based line:column), `sig main.jai:20:11` → every overload with the active parameter,
    `complete main.jai:42:7` (filtered by the typed prefix), `wsym squ` → `square  [procedure]  util.jai:3`
    (project files only).
  - `diag` → compiles the build root through Jails: `ok: no errors` or one line like
    `main.jai:19:11: error: Type mismatch. Type wanted: string; type given: s64.` (exit 1). It leaves `.build/`.
  - Options: `--root`, `--jails`, `--jai`, `--json` (raw LSP results), `--stats`, `--verbose`.
- Use it to answer "where is this defined / what are its parameters / what is in this file", especially into
  `~/jai/current/modules` where grep finds many candidates. Gaps: no hover, no references, no overload resolution,
  no polymorph or `context` awareness, inferred `.ENUM` after operators and variables from multiple returns do not
  resolve, code generated by metaprograms is invisible.
- **For errors after an edit, use the compiler**, not Jails: it is faster (no Node, no server start) and prints the
  full error with its context and notes; Jails `diag` reduces it to one line. Either way a program stops at its first
  error, so fix and recompile.
- Type-check without writing anything (verified: 0.15–0.18 s for example 25, no `.build/`, no executable) with a
  small `check.jai` kept outside the project:
  ```
  #import "Basic"; #import "Compiler"; #import "String";
  #run {
      set_build_options_dc(.{do_output = false});
      args := get_build_options().compile_time_command_line;      // jai check.jai - path/to/main.jai
      w := compiler_create_workspace("check");
      o := get_build_options(w);
      o.output_type = .NO_OUTPUT;
      paths: [..] string;                                         // a created workspace searches modules/ next
      array_add(*paths, tprint("%modules", path_strip_filename(args[0])));   // to the BUILD file: add the
      array_add(*paths, ..o.import_path);                         // project's own modules/ folder
      o.import_path = paths;
      set_build_options(o, w);
      add_build_file(args[0], w);
  }
  ```
  Projects that need `-import_dir` or their own build file: check with that build instead.
- **Security**: starting Jails compiles the project and runs its metaprogram code (`#run`, build files). Never run
  it (or the compiler) on code you do not trust. A custom `build.jai` that creates workspaces should skip output
  when `#exists(JAILS_DIAGNOSTICS_BUILD)`, or every Jails start rebuilds the project for real.

## 10. Reading the bundle

- `how_to/NNN_*.jai`: compile and run each lesson (`cd ~/jai/current/how_to && jai -quiet 019_looping.jai &&
  ./019_looping`); all runnable lessons work on Linux, all but 900 (x64 `#asm`) on the Mac; 495, 500 and 999 are
  prose. Stale prose: 019's paragraph on `for <` describes the pre-0.1.094 meaning (its code is right); 495 still
  shows `-plug` (use `+Name`).
- `modules/` is the API reference: `Preload.jai` (types the compiler needs: Type_Info, Allocator, Source_Code_Location,
  OS/CPU tags), `Runtime_Support.jai` (Context_Base, write_string, runtime error messages), `Basic/` (print,
  arrays, strings, memory, asserts), `Compiler/Compiler.jai` (Build_Options and the metaprogram API).
- Library ids: `jai-how-to`, `jai-modules-src`, `jai-examples-src`, `jai-changelog` (built from `~/jai/current`).
