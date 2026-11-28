# Writing and using modules (beta 0.2.032)

Everything here was compiled with 0.2.032 on macOS arm64 and Linux x64; the examples named in brackets are in
`examples/jai/jai-modules/` and pass on all three test machines. Ground truth: `how_to/040_import_and_load`,
`how_to/151_file_and_global_scopes`, `how_to/380_module_parameters`, `examples/import_replacement`
(`library_search query="..." sources=["jai-how-to","jai-examples-src"]`).

## 1. What a module is

- A **module** is code compiled in its own scope that can see only Preload and what it imports itself. It is
  always compiled **from source, with your program, every build** (no prebuilt module binaries, no version
  resolution). Native code a module uses comes in through `#library` (see c-interop.md).
- Two forms, found by `#import "Name"`:
  - single file: `<dir>/Name.jai`;
  - folder: `<dir>/Name/module.jai` (that file can `#load` more files of the same module).
  If both exist in the same search directory the import is an error: *"This module exists in both single-file and
  directory form, at the same point in the modules_path"* [08].
- `#load "file.jai"` is not an import: it adds the file to the **current** module (or program) with its own file
  scope. Use `#load` to split one module into files; use `#import` to use another module.

## 2. Import forms

| Form | Meaning |
|---|---|
| `#import "Basic";` | Search the import path; link all exported names into this scope (file scope after `#scope_file`, otherwise program/module scope). |
| `M :: #import "Math";` | Same module, but only the name `M` is added: `M.Vector3`, `M.length(v)` [01]. |
| `using M :: #import "Math";` | Both: names unqualified and `M.` available. In a module this **re-exports** them [05]. |
| `#import,file "vendor/util.jai";` | A file as a module, path relative to the file containing the directive (also inside `#load`ed files) [06]. Since 0.1.032; relative-to-file since 0.1.045. |
| `#import,dir "vendor/Shapes";` | A folder module (needs `module.jai`) by path [06]. |
| `#import,string "code";` | Compile a string literal (or `#string`) as a module [06]. Must be a literal at parse time. |
| `#import "Name"(A = 1)` | Module parameters (§5). |
| `#import "Basic"()(ENABLE_ASSERT = false)` | Program parameters (§5) [12]. |

- Importing the same module again with the same parameter text is free (deduplicated): one copy of its code and
  globals [09, 11].
- `#import` is also allowed inside a procedure body, with a surprise (checked): an **unqualified** import there
  still links the module's names at program level (another procedure, even one in a different `#load`ed file,
  could call `print` after `main` did `#import "Basic"`), while a **named** import (`M :: #import "Math";`) is a
  local constant visible only in that procedure. Imports inside code that is never compiled (a polymorph that is
  never instantiated) have no effect (changelog).
- Imports are **not transitive**: a module's own `#import "Basic"` does not give its importers `print` [04].

## 3. Where `#import "Name"` looks

Order checked with `get_build_options().import_path` [07]:

1. each `-import_dir DIR` from the command line, in order. A relative DIR is taken **relative to the first file
   you compile**, not the shell's working directory (Default_Metaprogram prefixes it).
2. `modules/` next to the first compiled file (since 0.1.080). No flag needed: the normal way to give a program
   its own or vendored modules [02].
3. the compiler's `modules/`.

The first match wins **for the whole workspace**, including imports made by bundled modules: a local
`modules/Hash.jai` replaced the bundled `Hash` that `Hash_Table` imports. That is how you patch a bundled module
(copy it, edit the copy), and also how you can break things by accident with a common name.

From a build metaprogram: set `options.import_path` on the target workspace (a `[] string`; build a `[..] string`
and assign it). `examples/wasm/first.jai` puts its own folder first; `remap_import(w, host, name, replacement)`
and `provide_import` (in a message loop handling `.FAILED_IMPORT`) redirect or synthesize imports
(`examples/import_replacement`; jai-metaprogramming).

## 4. Scopes inside a module

| Directive | Visible to | Typical use |
|---|---|---|
| `#scope_export` (default at the top of every file) | the whole module **and importers** | the API |
| `#scope_module` | every file of this module, not importers | shared helpers, module-wide globals, the module's own `#import`s |
| `#scope_file` | this file only | constants and helpers of one file |

- Error for a module-private name used by an importer: *"Undeclared identifier 'name'"* [03]. For a file-scoped
  name used from another file the compiler adds a hint pointing at the `#scope_file` declaration and suggests
  `#scope_export`.
- Put a module's own imports under `#scope_module` (or `#scope_file`) so they never look like part of the API.
  An `#import` under `#scope_export` still does not re-export: only `using X :: #import` or alias constants
  (`say :: B.print;`) do [05].
- `#load` is unaffected by the scope directive; each loaded file starts in `#scope_export`.

## 5. Module and program parameters

```jai
// modules/Counter/module.jai
#module_parameters (STEP := 1, LABEL := "counter") (VERBOSE := false);
count: int;
bump :: () -> int { count += STEP; #if VERBOSE print("[%] %\n", LABEL, count); return count; }
#scope_module
#import "Basic";
```

- First list = **module parameters**: chosen per `#import`; each distinct list compiles a **separate copy** of the
  module (own code, own globals). Second list = **program parameters**: set once, by the main program, and seen by
  every import of that module in the whole program [11].
- Parameters are compile-time constants inside the module (`#if VERBOSE`). Importers can read them through a
  named import (`Feet.SYSTEM`), not through an unqualified import [14].
- Deduplication compares the **text** of the argument list: `(STEP = 2, LABEL = "x")` and
  `(LABEL = "x", STEP = 2)` are two instances [11].
- Types used by parameters go in a block after the lists, compiled once and shared by all instances:
  `#module_parameters (UNITS := Unit.METERS) { Unit :: enum { METERS; FEET; } };` (since 0.1.075). Callers pass
  `.FEET`; the block's types are not exported to importers (0.2.032) [14].
- `#module_parameters` must be in the module's first file; putting it in a file `#load`ed first also worked.
- Errors, all checked: unknown name *"Argument name 'SIZ' (number 1) is not found in the module parameters."* [13];
  wrong type *"Type mismatch. Type wanted: s64; type given: string."*; parameters to a module without them
  *"...the imported module has no #module_parameters directive."*; program parameters from inside a module
  *"Program parameters can only be supplied from the main program."*; twice *"Cannot supply program parameters
  for the same module twice."*.
- Bundled examples worth copying: `Basic` (program parameters `ENABLE_ASSERT`, `MEMORY_DEBUGGER`, ...),
  `Hash_Table` (`COUNT_COLLISIONS`), `Thread`, `Simp` (`render_api`, with a common block), `Remap_Context`
  (`VERBOSE`), `Curl` (`LINUX_USE_SYSTEM_LIBRARY`).

## 6. Name collisions

| Situation (both modules imported unqualified) | Result [09, 10] |
|---|---|
| Same procedure name, different argument types | One overload set: works. |
| Same procedure name, identical argument lists | Error at the call (*"Procedure call matches 2 possible overloads"*) or at declaration (*"Two overloaded definitions of the same procedure can't have identical argument lists."*). Random + PCG `random_get()` is a real case. |
| Same constant / type / global name | *"Redeclaration of 'VERSION'"* as soon as both are imported, even if unused. |
| Your program declares a name a module exports | Redeclaration error at application scope; a `#scope_file` declaration in your file **shadows** the import silently. |

Fix: name the import (`Old :: #import "Old_Format";`) or import it under `#scope_file` in the one file that needs
it. Do not prefix names inside your module to avoid clashes: importers choose the namespace.

## 7. Layout of a good module

```
modules/My_Thing/
  module.jai        API at #scope_export; #module_parameters first if any; #load of the rest;
                    #scope_module + its own #imports at the bottom
  platform_*.jai    #if OS == { case .WINDOWS; #load "platform_windows.jai"; ... }
  bindings.jai      generated code, if any, with generate.jai next to it
  macos/ linux/ windows/   native libraries per OS, chosen with #if OS around #library
  examples/         small programs that compile (bundled modules do this)
```

- Keep the exported surface small (`#scope_module` for internals). Return values in the success-first style newer
  APIs use (`found, value := table_find(...)`).
- Allocate with `context.allocator` and accept the `,,` context arguments callers will push
  (`f(x,, temp)`); never take an `allocator` parameter (removed style; see jai-systems).
- Platform branches with `#if OS == { case ...; }` (since 0.1.084) or `#if OS_IS_UNIX`; the untaken branches are
  not compiled at all [37].
- Tests: a `tests.jai` or `examples/` program; for a test runner see the community `stubborn` module (§9).

## 8. Third-party modules: vendoring

There is no package manager. Use a community module by **copying it into your project** and adding the folder to
the search path:

```
my_app/
  first.jai
  modules/jaison/          <- vendored copy (found without flags), or
  third_party/uniform/     <- jai first.jai -import_dir third_party   (or import_path in build.jai)
```

- Pin what you copied (commit hash in a README next to it). Keep the folder name the module's docs expect: modules
  import each other by name (e.g. jai-simplehttp expects to be `SimpleHTTP` and imports `uniform`).
- Checked in scratch: rluba's **jaison** (MIT) vendored under `third_party/` with `-import_dir third_party`:
  typed `json_parse_string(text, Config)` and `json_write_string` worked unchanged on 0.2.032; its own
  `#import,dir "./unicode_utils"` keeps working after the copy because the path is relative to its file.
- Expect breakage after a compiler upgrade, and fix the vendored copy: 0.2.032 renamed `New/NewArray`'s
  `initialized` parameter to `initialize` (no deprecation), which broke rluba's uniform, jai-postgres and focus the
  week it shipped. The error points into the vendored file: *"Argument name 'initialized' (number 3) is not found
  in the procedure being called."* [40]; checked on a vendored uniform: one-word fix, then it compiled and matched.
- **Is it current?** Check, in this order: (1) last commit date vs the compiler's CHANGELOG
  (`library_search query="..." sources=["jai-changelog"]`); (2) compile its example/tests with your compiler;
  (3) grep for stale forms: `<<` dereference, `#place`, `#must`, bare `Context`, `get_time`, `allocator =` arguments,
  `make_vector2(`, `#foreign_library`, `.loose`, `Tagged_Union`, `value, found := table_find`, `initialized =`,
  `for < n..0` (reverse ranges changed meaning), `x64 #asm` without `#if CPU == .X64` (fails on Apple Silicon).
- License: most are MIT/Apache-2.0; focus is GPL-3.0 (read it, don't paste it into permissive code); several have
  no license (private use only).

## 9. Community modules (status on 0.2.032, from the sources scout, 27 Nov 2026)

| Project | What | Status on 0.2.032 | Library id |
|---|---|---|---|
| rluba/jaison | JSON (generic and typed via Type_Info, member notes for renaming) | compiles, tests pass | `jaison-source` |
| rluba/uniform | Regular expressions (RE2-style NFA) | needs the one-word `initialize` fix, then 146 tests pass | `uniform-regex-source` |
| rluba/stubborn | Compile-time test runner (`@Test` in `*.spec.jai`) | compiles (drives uniform's tests) | `stubborn-source` |
| rluba/jai-csv | Typed CSV reader | not built separately | `jai-csv-source` |
| rluba/hyperserve | HTTP server framework (author: unfinished) | not built | `hyperserve-source` |
| smari/jai-xml | XML DOM parser | on Apple Silicon import with `(USE_SIMD_STRING_SEARCH = false)` (default uses x64 `#asm`) | `jai-xml-source` |
| smari/jai-simplehttp | Small HTTP server on the bundled Socket module | compiles when placed as `modules/SimpleHTTP` with uniform available | `jai-simplehttp-source` |
| valignatev/jai-on-linux | Generated X11/xcb/Wayland/xkb bindings, GDB pretty printers | Linux; xcb example builds | `jai-on-linux-source` |
| focus-editor/focus | Large real program (text editor), GPL-3.0 | needs the `initialize` fix; builds `.app` | `focus-editor-source` |
| SogoCZE/Jails | Language server (LSP) for editors | compiles, answers LSP | (see jai skill) |

Finding more: `awesome-jai` (link list, many entries abandoned), the Jai Community wiki's *References* page
(`jai-community-wiki`, dated), `jai-encyclopedia-of-examples` (current, idiomatic). `the-way-to-jai` (Apache-2.0)
has a modules chapter checked against 0.2.024 but later chapters teach removed features.
