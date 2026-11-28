---
name: jai
description: Write, build, explain, modernize and probe Jai (Jonathan Blow's language, closed beta 0.2.032) correctly — installing a beta (~/jai/current, macOS quarantine, Linux x86-64 only), the jai command line (LLVM vs -x64 backend, -o/-od/-very_debug, -quiet, -import_dir, -run, +Autorun/+Rewrite plugins, args after -, version only on a terminal), error formats, build file vs default metaprogram; the core language: declarations (::, :=, = ---), numbers and literals, casts (cast, xx, cast,no_check, cast,trunc), strings and #string, arrays ([N]T, []T, [..]T), structs, using/#as, enums/enum_flags/#complete, unions/#overlay/tagged unions, pointers (*x, p.*), procedures (multiple returns, named and default args, overloading, operators), for/it/it_index/for </remove, if == case/#through, ifx, defer, Any/Type/type_info, context and print formatting, runtime checks per build mode; false friends from C, C++, Odin and Go with real compiler errors and a Jai-vs-Odin table; recognizing and updating old Jai code (<<, #place, Context, allocator= params, table_find order, silent for < change); navigating code with Jails; teaching and probing Jai with small experiments. Load before writing, reviewing, explaining, updating or debugging any Jai code.
---

# Jai (core language and toolchain)

## Ground truth first

- Validated with **beta 0.2.032 (26 Nov 2026)** on macOS arm64 (`~/jai/current/bin/jai-macos`) and Linux x86-64
  (`jai-linux` on Obarun and Ubuntu 26.10, glibc 2.44). Every snippet here compiled; every quoted message is real
  compiler output. Nothing was tested on Windows or Linux arm64.
- Your memory of Jai is stale, and so is most material online. Since 2023: postfix `p.*` (0.1.065) and prefix
  `(.*) p` (0.2.004) replaced `<<`; dot-less literals `{1, 2}` (0.2.022) and `[1, 2]` (0.2.031); `%%` now means two
  arguments (0.2.022); `#must` and `#place` are gone; tagged unions (0.2.023); `for < a..b` changed meaning (0.1.094).
  See "Reading and modernizing old Jai code" below. Mark version-sensitive facts "(0.2.032)".
- **Check the version** (it prints only to a terminal; `jai -version | cat` prints nothing):
  `script -q /dev/null ~/jai/current/bin/jai-macos -version` (macOS),
  `script -qc "~/jai/current/bin/jai-linux -version" /dev/null` (Linux) →
  `Version: beta 0.2.032, built on 26 November 2026.` Pipe-safe: a file importing Basic and Compiler with
  `#run { print("%\n", compiler_get_version_info(null)); set_build_options_dc(.{do_output = false}); }`.
- **The bundle is the documentation**: `~/jai/current/how_to/` (67 lessons, read in order), `modules/` (all
  source), `CHANGELOG.txt`, `modules/Default_Metaprogram.jai` (the command line). Search it with the library:
  `library_search query="array_unordered_remove_by_index" sources=["jai-modules-src"]` (exact signatures),
  `sources=["jai-how-to"]` (lessons), `["jai-changelog"]` ("when did X change?"), `["jai-examples-src"]`, then
  `library_read`. Or grep: `grep -rn "^array_add ::" ~/jai/current/modules/Basic`. **Read the module source for
  exact signatures; never guess.**
- The bundle is private (Copyright.txt): read it locally; never paste its text or code into public files.

## Install and run (deep dive: reference/toolchain.md)

- Unpack to `~/jai/beta-0.2.032`, symlink `~/jai/current` to it, run `~/jai/current/bin/jai-macos` / `jai-linux`.
  macOS: clear quarantine once (`xattr -dr com.apple.quarantine <dir>` or the bundle's `macos_de-quarantine.sh`);
  links with Xcode's `ld` (via `xcrun`) and writes `name.dSYM`. Linux: bundled `lld-linux`, x86-64 only, needs a
  glibc at least as new as Ubuntu 20.04's (the README's "18.04" is outdated).
- `jai main.jai` builds `./main` next to the source (objects in `.build/`). The compiler first changes directory to the
  main file's folder, so `#load` paths, `-output_path` and `-import_dir` are relative to it. Success prints the
  linker line and a stats block (`-quiet` silences both). Errors go to **stderr** as `path:line,col: Error: …` plus a
  caret excerpt, exit 1 (`-msvc_format`: `path(line,col)`). One file reports only its **first** error.
- Build modes: default = debug (runtime checks on, LLVM -O0, stack traces); `-o` (`-optimized`; the help text's
  `-optimzed` is a typo) = LLVM -O3, **all runtime checks and stack traces off**; `-od` = optimized, keeps stack
  traces (checks off); `-very_debug` = the same checks as debug in 0.2.032. Backends: LLVM (default) or `-x64`
  (fast in-house codegen, **x86-64 only**; on an Apple Silicon Mac: "The x64 backend supports only x64 CPUs but the
  CPU target was set to ARM64 (4)"). Measured on Linux: codegen 0.002 s (x64) vs 0.09 s (LLVM) vs 0.5 s (`-o`);
  the program ran 1.25 s / 0.68 s / 0.34 s.
- Flags: `-exe name`, `-output_path dir` (must exist), `-import_dir dir`, `-add "X :: 1;"`, `-run 'code'`,
  `-no_check`, `-output_ir` (`.ll` into `.build/`), `-no_split`, `-no_inline`, `-natvis`, `-verbose`; plugins after
  the options (`+Autorun` runs the program, `+Rewrite` migrates `<<`); arguments after a lone `-` go to the
  metaprogram (`get_build_options().compile_time_command_line`). `jai -- help` lists the hidden developer options.
- A **build file** (`jai build.jai`) creates its own workspace and sets `Build_Options` in code; it must call
  `set_build_options_dc(.{do_output = false});` (else "No program entry point was found"). The print-checking
  Check plugin runs only in the default metaprogram's workspace. Example 26; depth: **jai-metaprogramming**.

## Program shape

- Entry point `main :: () {…}`; it cannot return a value ("Entry point must not return a value"): call `exit(code)`.
  Without `#import "Basic"` only `write_string`/`write_number` (Runtime_Support) and Preload exist.
- `#import "Name"` loads `modules/Name.jai` or `modules/Name/module.jai` into its own sealed scope (a module sees only
  what it imports). `#load "file.jai"` adds a file to the current program or module. Named import:
  `Math :: #import "Math";` → `Math.sqrt(x)`. Also `#import,file "x.jai"`, `#import,dir "lib/M"`,
  `#import,string "…"`. A `modules/` folder next to the main file is searched automatically; others need
  `-import_dir`. Parameters: `#import "Basic"()(ENABLE_ASSERT=false);` (program parameter, first import).
- Scopes: `#scope_file` (this file only), `#scope_export` (default), `#scope_module` (whole module, not exported).
  File-scope declarations are order-independent; inside a procedure, declare local constants before use.
  Example 25 is a small project layout.

## Language essentials (complete tour with tested snippets: reference/language-tour.md)

- **Declarations**: `x: int;` (zeroed) · `x := 5;` · `X :: 5;` (constant; procedures, structs, enums too) ·
  `X : float64 : 2.5;` · `buf: [1024] u8 = ---;` (uninitialized) · `a, b := 1, 2;` · `x, y: int = 7;` (both 7) ·
  `a, b = b, a;`. `x := 5; x := 6;` → "Redeclaration of 'x'."
- **Numbers**: s8…s64, u8…u64, `int` = s64, `float` = float32, float64. Integer literals are s64, float literals
  float32 unless they need float64. `0xFF`, `0b1010`, `1_000_000`, `0h7FC0_0000` (raw IEEE bits), `1.0e5` (`1e5`
  does not parse), `#char "A"` (65, type s64). S64_MAX, U8_MAX, PI … live in module **Math**. Division truncates
  toward zero; shifts by the bit width or more give 0.
- **Conversions**: implicit only when no value is lost (u8→s32 yes; s64→s32, s8→u64, int→float, u8+s8 no).
  Literals and `::` constants convert when the value fits. Otherwise `cast(T) x`, `xx x` (to whatever type the context
  needs), `cast,no_check(T)` / `cast,trunc(T)` (keep the low bits). Debug builds range-check `cast` and `xx` at run
  time ("Cast bounds check failed.  Number must be in [0, 255]; it was 1000.", exit 1); constant casts are checked
  at compile time. Struct-to-struct needs `cast,force`. Examples 04, 05.
- **Strings**: `string` = `{count: s64; data: *u8}`, a view: no zero terminator, `s[i]` is a u8, assignment copies
  the view, literals are read-only (`copy_string` to edit). Only `==`/`!=` work on strings: `compare`, `join`,
  `split`, `find_index_from_left` (module String); `sprint` (heap), `tprint` (temporary), String_Builder
  (`append`, `print_to_builder`, `builder_to_string`). For C: `to_c_string(s)` allocates, `to_string(p)` wraps a
  `*u8`, constant literals pass as `*u8`. `#string END … END` is verbatim and ends with a newline. Examples 06, 07.
- **Arrays**: `[N] T` fixed · `[] T` view `{count, data}` (what procedures take) · `[..] T` resizable (`count, data,
  allocated, allocator`, 40 bytes). Literals `int.[1, 2]`, or `[1, 2]` / `.[1, 2]` when the type is known.
  `array_add(*a, x)` (pass the address), `array_find`, `array_insert_at`, `array_ordered_remove_by_index`,
  `array_unordered_remove_by_index`, `pop`, `array_reserve`, `array_reset` (frees), `NewArray(n, T)`. Growth moves
  the elements: no pointers or views into a `[..]` across `array_add`. Examples 08, 09.
- **Structs**: `V :: struct { x, y: float; name := "a"; }`; the body may override nested defaults (`pos.y = 5;`).
  `V.{1, 2, "b"}` (positional: every member), `V.{y = 3}` (named), `{1, 2, "b"}` where the type is known, `{}` = all
  defaults. Assignment copies bytes; no constructors, no built-in `==`. `using` pulls members into scope;
  `#as using base: Base;` also converts implicitly to the base. Examples 10, 11.
- **Enums**: `E :: enum u8 { A; B :: 10; C; }` (C = 11), `enum_flags` (1, 2, 4 …; `|`, `& ~.X`), `#specified`
  (every value explicit), `.NAME` where the type is known (`z := .A;` alone fails), `enum_names(E)`,
  `enum_range(E)`. Example 12. **Unions**: plain `union {…}`; in structs `#overlay (member) view: T;`; tagged
  `union kind: Kind { .A ,, a: int; … }` (no checked access yet). Example 19.
- **Pointers**: type `*T`; address `*x` (no `&`); dereference `p.*` or `(.*) p`; `.` dereferences one level for
  members (no `->`); `p + 1` steps one element; `null`; `New(T)` / `free(p)`. `[]` on a pointer does C pointer
  indexing (no warning): on `ap: *[4] int` write `ap.*[i]`. Example 13.
- **Procedures**: `f :: (a: int, b := 2) -> int {…}`; several returns `-> q: int, r: int` with `return x, y;` and
  `q, r := f();` (trailing ones may be dropped); return defaults (`-> a: int = 1`, bare `return;`). Named arguments
  in any order; varargs `(xs: ..int)` is a `[] int`, spread with `f(..arr)`. Overload by declaring the same name
  again. Procedure types `(int) -> int`; lambdas `x => x * 2` (polymorphic, capture nothing). Nested procedures
  cannot see the caller's locals ("Attempt to use a variable from an outer stack frame. (Closures are not
  supported.)"). Large arguments (strings, structs, Any) are read-only in the callee ("Can't assign to an
  immutable argument."). `inline`/`no_inline` at declaration or call. Examples 14, 15.
- **Operators**: `operator + :: (a: V, b: V) -> V`; `+=` falls back to `+`, `!=` to `==`; `#symmetric` swaps
  operands; `operator *[] :: (r: *R, i: int) -> *T` gives reads and writes. One operand must be a struct.
- **Control flow**: `for 1..3` (inclusive; `it`), `for < 1..3` (3 2 1; the range is still low..high), `for arr`
  (`it`, `it_index`; read-only), `for v, i: arr`, `for * arr { it.* += 1; }`, `remove it;` (unordered), named loops
  (`for row: …` then `break row`), `while c {}`, `defer` (end of scope, reverse order, every exit path). Switch:
  `if x == { case 1; … case; … }` (no fallthrough unless `#through;`; constant cases; strings, enums, Types;
  `if #complete e == {}`; `break` leaves the loop). Expression if: `ifx c then a else b`. No `?:`, `++`,
  `do … while`, C `for (;;)`. Examples 16–18.
- **Types at run time**: `Type` values (`t: Type = int`, `type_of(x)`, `T == s64`), `type_info(T)` (members,
  offsets, enum names), `Any` = `{type, value_pointer}` (points at the value), `size_of(T)` takes a Type. Example 20.
- **Compile time**: `X :: #run f();`, `#assert cond;`, `#if`/`#ifx`, `is_constant(x)`, `OS`, `CPU`. Example 24;
  depth: **jai-metaprogramming**.

## Printing, context, checks

- `print("% and %\n", a, b)`: `%` is the whole placeholder (`%d` prints a literal `d`), `%2` = argument 2, `%0` =
  next, `%%` = two arguments back to back, `\%` = a percent sign. Formatting wraps the value: `formatInt(x, base=16,
  minimum_digits=4)`, `formatFloat(f, trailing_width=2)`, `formatStruct(v, …)`, or `FormatInt.{value=x, base=16}`;
  defaults live in `context.print_style`. Too few arguments is a compile error (Check plugin); too many only warns.
  `log` → stdout, `log_error` → stderr. Example 22.
- `context` reaches every procedure except `#c_call`/`#no_context` ones: `allocator`, `temporary_storage`, `logger`,
  `stack_trace`, `thread_index`, `print_style`, plus `#add_context x: T;`. `push_context c {…}` scopes a modified
  copy; `f(x,, allocator = a)` (or `f(x,, a)`) changes it for one call; `push_allocator(a)` until scope end. Use
  `tprint`/`temp` and `reset_temporary_storage()` for short-lived memory. Example 21; depth: **jai-systems**.

| build | array bounds | cast range | null (auto-deref of args) | integer overflow | stack traces |
|---|---|---|---|---|---|
| default, `-very_debug` | fatal, exit 1 | fatal, exit 1 | fatal | **off (wraps)** | on |
| `-od` | off | off | off | off | on |
| `-o` | off | off | off | off | off |

- Explicit `p.*` on null is a plain crash in debug builds (exit 1); with `-o`/`-od` it is undefined behaviour (one
  probe's null store vanished: exit 0, no output; another became a trap). Overflow checks need a build file:
  `options.arithmetic_overflow_check = .FATAL` (example 26). `assert(cond, "fmt %", x)` prints
  `file:line,col: Assertion failed: …` with a stack trace, exit 1 (example 28). `#no_abc` skips bounds checks.

## False friends (full list: reference/false-friends.md; examples 50–57)

| habit | Jai | compiler says |
|---|---|---|
| `&x`, `*p`, `p->f` | `*x`, `p.*`, `p.f` | "Expected an expression after '='." / "Mismatching levels of indirection" / "Semicolon expected after expression." |
| `i++` | `i += 1;` | "Error in unary expression." |
| `int x = 5;`, `switch x {}`, `for x in a` | `x: int = 5;`, `if x == {}`, `for x: a` | "This looks like a C-style declaration (two identifiers in a row)…" |
| `c ? a : b`, `x or_return` | `ifx c then a else b`, explicit checks | "We parsed a declaration, so we expected a semicolon after it…" |
| `for (i=0;…)`, `0..<n` | `for i: 0..n-1` | "',' expected." / "Expected an expression after '..'." |
| `NULL`, `nil`, `nullptr`, `sizeof`, `len` | `null`, `size_of(type_of(x))`, `.count` | "Undeclared identifier …" |
| `u8(x)` | `cast(u8) x`, `xx x` | "To instantiate a type with arguments, that type must be a struct." |
| `"a" + "b"`, `s1 < s2` | `join`, `tprint("%%", a, b)`, `compare` | "Operator '+' does not work on strings." |
| struct `==` | `operator ==` | "Procedure call did not match any of the possible overloads." |
| capturing lambda | pass a parameter | "…outer stack frame. (Closures are not supported.)" |
| `int main()` | `exit(n)` | "Entry point must not return a value." |
| `printf("%d")`, `for arr it = 0;`, `ap[i]` on `*[N]T` | `print("%")`, `for *`, `ap.*[i]` | silently wrong (example 57) |

**Jai vs Odin** (similar ideas, different spelling; see the odin skill only for contrast): `proc(a: int)` →
`(a: int)`; `package` + `import "core:fmt"` → `#import "Basic"`, files via `#load`; `^T`, `p^` → `*T`, `p.*`;
`fmt.println(x)` → `print("%\n", x)`; `for x in a` / `for &x in a` → `for x: a` / `for * a`; `switch` →
`if x == {}`; `len(a)` → `a.count`; `[dynamic]T` + `append` → `[..]T` + `array_add`; `make`/`new` →
`NewArray`/`New`; `distinct` → `#type,distinct`; `when` → `#if`; `or_return` → explicit checks; `transmute` →
`#overlay` or pointer casts; `#packed` → member `#align 1` (and `} #no_padding` for trailing padding);
`"contextless"` → `#no_context` (`#c_call` for the C ABI); `defer` and `context` exist in both.

## Reading and modernizing old Jai code (deep dive: reference/false-friends.md; examples 58, 59)

Most Jai online (talks 2014–2020, blogs, the community wiki, chapters 9+ of the-way-to-jai) predates 2025. Signals
and fixes, with the beta that changed them:

| old | current | |
|---|---|---|
| `<< p`, `<< cast(*T) q` | `p.*` / `(.*) p`, `(cast(*T) q).*` | warns since 0.2.022; `jai f.jai -no_dce +Rewrite -write` rewrites |
| `for < 10..0` (count down) | `for < 0..10` | **silent**: old form runs 0 times (0.1.094) |
| `value, found := table_find(*t, k)` | `found, value := table_find(*t, k)` | **silent** when types fit (0.2.018) |
| `print("100%%")`, `%0%` hacks | `print("100\%")`, `%%` | `%%` = two arguments (0.2.022) |
| `#place x; y: T;` | `#overlay (x) y: T;` | removed 0.2.027 |
| `#must`, `p.?f`, `E.loose`, `#run_and_insert` | remove / null check / `type_info(E)` / `#insert #run` | removed |
| `c: Context` | `#Context` / `Context_Base` | 0.2.002 |
| `copy_string(s, allocator = a)` | `copy_string(s,, a)` | 0.1.080 |
| `New(T, initialized = false)` | `initialize = false` | 0.2.032 (breaks current repos) |
| `using base: Base;` as inheritance | `#as using base: Base;` | 0.1.033 |
| `xx` between structs | `cast,force(B) a` | |
| `-> void { return; }` | omit the return type | "Not enough return values: Wanted 1, got 0." |
| `#foreign_library`, `#foreign_system_library` | `#library "x"`, `#library,system "libc"` | 0.2.002 |
| `get_time`, `Swap`, `__temporary_allocator`, `bubble_sort` | `seconds_since_init`, `swap`, `temp`, `quick_sort` | removed |
| `Tagged_Union` module | `union kind: Enum { .A ,, a: T; }` | 0.2.025 |
| `-plug X`, `-- args`, `-release` | `+X`, `- args`, `-o` | 0.2.012, 0.1.048, 0.2.026 |

Still accepted, avoid in new code: `.{…}`/`.[…]` (dot optional when typed), `#char "x"` (a one-character string
converts to u8), `cast(T, x)` and `x.(T)` (0.2.005 experiment; modules use `cast(T) x`), `#v2` and Hash_Table
`init()` (warn). Third-party code: expect the 0.2.032 `initialized` rename and `table_find` order first.

## Navigating Jai code (details: reference/toolchain.md)

- Jails (the Jai language server) is installed at `~/jai/tools/jails/current/jails`; OpenCode V2 runs no language
  servers, so use the shell front end:
  `pixi exec --spec nodejs=24 node <oc-knowhow>/scripts/jails-query.mjs def main.jai print` →
  `$JAI/modules/Basic/Print.jai:326:1: print :: (…)`; also `symbols <file>`, `def <file>:<line>:<col>`,
  `sig <file>:<line>:<col>`, `complete <file>:<line>:<col>`, `wsym <query>`, `diag`. About 1–2 s per call.
- For errors after an edit, run the compiler (fast, prints every workspace's errors with context); Jails `diag`
  shows only one error. Jails compiles the project and runs its metaprogram: **never use it on untrusted code**.

## Idioms and taste

- Flat data by value in arrays, `[]` views as parameters, `[..]` only where things grow; indices or handles instead
  of pointers into growing arrays.
- Allocate from `context.allocator`, put `defer free(x)` next to the allocation, use `tprint`/`temp` for
  per-frame data, let callers pick the allocator with `,,`.
- Multiple returns for value + status (success first in new APIs), `ifx` for one-value choices, `#complete` on enum
  switches, `#specified` on serialized enums, named arguments for long parameter lists.
- `for` and `for *` over index loops; no unsigned `0..n-1` (n = 0 wraps); never `array_add` to the array you iterate.
- Hermetic modules: import what each file uses, `#scope_file` helpers, named imports to resolve clashes.

## Teaching and probing (method and probe list: reference/probing.md)

- Explain in 2–4 sentences, show the smallest program that runs, then propose an experiment ("delete the `*`,
  compile, read the error"). Compiler errors are precise and teach well.
- Tools: `print("%\n", type_of(expr))`, `size_of(T)`, `type_info(T)`, `#assert`, `#run { print(…); }` (prints while
  compiling), `is_constant`, `-x64` vs LLVM, `-output_ir`, default vs `-o` for checks. One workspace per snippet
  compiles many wrong forms at once (examples 51, 52, 56, 58).
- Before claiming behaviour, read the matching how_to lesson and module source, then confirm with a probe.

## Where to look

| topic | how_to | module source |
|---|---|---|
| declarations, numbers, literal types | 001, 002, 085, 090 | Preload.jai |
| arrays, strings, array literals | 004, 005, 015 | Basic/Array.jai, Basic/Simple_String.jai, String/module.jai |
| structs, literals, `using` | 006, 007, 042, 044 | — |
| procedures, parameters | 010, 250, 093, 094, 050 | — |
| context, temp storage, memory | 011, 012, 200, 225, 800 | Runtime_Support.jai (Context_Base), Basic/module.jai |
| enums, unary dot, Any, Type | 013, 014, 008, 020, 030, 180 | Preload.jai |
| print, logging, stack traces | 018, 350, 700 | Basic/Print.jai |
| loops, if, ifx, case | 019 (its `for <` prose is stale), 022, 025, 027 | — |
| import/load, scopes, module params | 040, 080, 151, 380 | Default_Metaprogram.jai |
| static if, polymorphism | 095, 100–120, 160 | (jai-metaprogramming) |
| command line, build files | 420, 495 (still says `-plug`: use `+Name`), 400, 950 | Default_Metaprogram.jai, Compiler/Compiler.jai |

All runnable lessons build and run on Linux; on the Mac all but 900 (x64 `#asm`). Outside the bundle (library ids):
`jai-encyclopedia-of-examples` (current, idiomatic), `the-way-to-jai` (Apache-2.0, dated: fine through §8, later
chapters teach removed features), `jai-parser-source` (its tests list current syntax), `jails-source`,
`jaison-source`/`stubborn-source` (reflection, compile-time tests), `jaibreak-source` (an "update old code"
exercise), `jai-community-wiki` (dated), `jai-blog-smari-four-years`; the user's own library folders, if added.

## Examples and siblings

- `examples/jai/jai/`: 01–30 one idea each; 50–57 false friends; 58–59 old Jai. Run
  `pixi run jai-examples -- --skill jai` (0.2.032: Mac 39 ok + 1 Linux-only; powerslabs and ubuntu-laptop 40/40).
- Siblings: **jai-metaprogramming** (#run, polymorphism, #insert, #modify, workspaces, plugins), **jai-systems**
  (context, allocators, temporary storage, performance, profiling, threads, debugging), **jai-modules** (Basic,
  String, File, Hash_Table, Math, Command_Line …, writing modules, C interop and bindings, platforms). Contrast only:
  **odin**. Profiling with Tracy from C: **c-perf**.
