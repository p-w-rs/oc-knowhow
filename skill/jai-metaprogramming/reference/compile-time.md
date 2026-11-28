# Compile-time execution in depth (#run, #assert, #if, constancy)

Validated on Jai beta 0.2.032 (macOS arm64, Linux x86-64). Example numbers refer to
`examples/jai/jai-metaprogramming/`. Lessons: how_to/095 (#if), 500 (when not to), 550/551 (constancy), 560
(#no_reset); the changelog has the history ("since").

## The forms of #run

| Form | Where | Result |
|---|---|---|
| `X :: #run f(args);` | anywhere a constant can go | constant of f's return type |
| `#run f();` / `#run { ... }` | file scope or inside procedures | side effects only |
| `X :: #run -> T { ...; return v; };` | anywhere | anonymous procedure body, constant of type T |
| `#insert #run g();` | statement, expression, struct, enum, file scope | g returns a string (or Code) that is compiled in place |
| `#insert -> string { ... }` | same | short form of `#insert #run () -> string { ... }();` |
| `#assert #run check();` | file scope | a compile-time test (44) |
| `#run,stallable` | (used by Default_Metaprogram for its build()) | lets two #runs that wait on each other proceed (0.0.038); not probed here |
| `#run,host` | when cross-compiling | runs with the host's settings (how_to/950, documented 0.2.030; `jai-modules` skill). In a native build it behaves like `#run` (`X :: #run,host 6 * 7;` gave 42). |

- A #run inside a polymorphic procedure runs once per polymorph (each distinct set of parameters), not per call (09).
- A #run inside a procedure body is still a separate procedure: it sees constants (`::`), types and globals, never the
  enclosing locals ("Attempt to use a variable from an outer stack frame. (Closures are not supported.)").
- Order: compilation follows dependencies. Two file-scope `#run`s may run in any order (02 initially failed because
  the reader of a file ran before its writer). Make dependencies explicit: `WROTE :: #run write();` and have the
  reader use `WROTE`.

## What crosses from compile time into the program

Values returned from #run are serialized into the program's constant data (verified in 01 and 03):

- Fine: integers, floats, bools, enums, strings (copied), `Type` values, fixed arrays, structs and arrays of those.
- `[]` and `[..]` results become a constant fixed array (`type_of` prints `[6] s64`). Above
  `Build_Options.maximum_array_count_before_compile_time_returns_are_not_reflected_in_ast` (default 5000) elements
  the data is not mirrored into the syntax tree (a compile-speed measure for big tables).
- Pointers: a pointer into memory the #run allocated cannot be represented. The compiler warns ("Returned a pointer
  literal from compile-time execution that could not be mapped to a global variable"), compiles anyway, and using
  the pointer at run time is a crash. Pointers to known globals are remapped (`P :: *some_global;` works).
- Unions: returning any union from #run warns "It is illegal to return an untagged union from compile-time
  execution" (check added in 0.2.023, announced to become an error). That includes the new **tagged** unions
  (`union kind: Kind {...}`, 08), whose payload is lost: a value built as `.{.INT, 42}` arrived as `{INT, 0}` on
  macOS and Linux (03). Return the tag and payload as separate plain values, or a struct without a union.
- Globals: everything a #run writes into globals is **reset** to the declared initial values when the executable
  is written (since 0.0.070, earlier betas leaked state). Exception: `#no_reset name: T;` keeps the compile-time
  value (0.0.052; 03). Not allowed on struct members (0.1.038). Pointers inside #no_reset data are not remapped: a
  `#no_reset s: string` assigned a `sprint` result at compile time crashed at run time (SIGBUS) when printed.

## Side effects and environment

- `print` inside #run goes to the compiler's stdout (EXPECT-COMPILE in the examples checks it).
- The working directory is the folder of the first file given to the compiler (Default_Metaprogram changes to it),
  so `write_entire_file("x.txt", ...)` lands next to the source. `#filepath` (folder of the current file, trailing
  slash) and `#file` (full path) make file access independent of that.
- Anything in Basic, File, String, Process, Compiler... can run. A procedure marked `#compile_time` emits no machine
  code (0.1.081), `#compile_time` as an expression is true in the interpreter (0.1.034; replaced
  `running_at_compile_time()`, removed 0.1.043).
- Procedures marked `#compiler` (most of modules/Compiler) only exist at compile time. Calling one from run-time code
  compiles and then panics at run time ("Attempt to call a compile-time procedure at runtime"); with
  `Build_Options.prevent_compile_time_calls_from_runtime = true` it is a compile error that suggests wrapping the call
  in `if #compile_time { ... }`.

## Constancy (what #if, #assert, $ bakes and #insert accept)

Verified with a `$$x` probe and `is_constant(x)`:

| Constant | Not constant |
|---|---|
| literals, `::` declarations, operators on constants | any `:=` variable, even `x := 3` |
| `type_of(e)`, `size_of(T)`, `type_info(T)`, `type_info(T).type`, `.runtime_size`, `initializer_of(T)` | most other reads through type_info (members etc.) |
| `#run` results, `#location(...)`, `#this`, `#procedure_name()` | reading a member of a constant struct literal (`L.a`) |
| constant string `.count`, `[i]` with constant i | address of a local |
| fixed-array literal `.count` (even with non-constant elements) | casting a pointer to an integer |
| address of a global, constant pointer ± constant | dereferencing a constant pointer |

- `is_constant(e)` is itself constant and does not evaluate e (it does run a `#run` inside e).
- `$$name` arguments are constant exactly when the caller passed a constant; combine with `#if is_constant(name)`.

## #assert

- Syntax: `#assert condition;` or `#assert condition "message";`. The parenthesized C form with a comma fails with
  "Comma-separated expressions in an impermissible place" (05). Failure text: `Compile-time assertion failed.
  "message"` with the source excerpt (04).
- Common uses: layout checks (`size_of(T)`; there is no `offset_of` (0.2.032): read
  `Type_Info_Struct_Member.offset_in_bytes` in a `#run` helper), checking `$` parameters in polymorphs
  (`#assert n > 0 "…"`), rejecting For_Flags in a for_expansion (27), compile-time tests (`#assert #run self_test();`,
  44). A plain `assert` inside the #run of a test prints the run-time style message plus stack trace and fails the
  build (exit 1).
- An #assert inside a polymorphic body fires only after the polymorph was chosen; it cannot steer overload
  resolution (use `#modify` for that).

## #if and #ifx

- Condition must be constant ("Condition of #if is not constant.", 07).
- The braces do not create a scope: declarations in the chosen branch are visible after it (06). This is how
  per-platform procedures with the same name are written (`#if OS == .WINDOWS { f :: () {...} } else { f :: ... }`).
- Both branches must parse; only the chosen one is typechecked, so the other may use undeclared names.
- Works in procedure bodies, at file scope, inside structs (conditional members) and enums (conditional members).
- `else #if` chains, or a static switch (since 0.1.084; verified on 0.2.032):
  `#if MODE == { case 1; ...; case 2; ...; case; ...; }`. (The prose of how_to/095 still says the switch form is
  unsupported: stale.)
- `#ifx cond then a else b` is an expression; the block form `#ifx cond { ...; value; } else { ...; value; }` yields
  the last expression of the chosen block.
- Built-in constants for conditions: `OS` (.MACOS, .LINUX, .WINDOWS, ...), `CPU` (.X64, .ARM64), plus module
  parameters and anything `::` (the `jai-modules` skill covers `OS`/`CPU` when cross-compiling).

## Errors and exit codes

| Situation | Output | Exit |
|---|---|---|
| failed `#assert` | `file:line,col: Error: Compile-time assertion failed. "msg"` | 1 |
| failed `assert` inside #run | `Assertion failed: msg`, stack trace, `There were errors on Workspace 2. Exiting.` | 1 |
| crash inside #run (null write) | `This crash happened during compile-time execution of Workspace #2 ...`, hint to use `-debugger` | 3 |
| `compiler_report(...)` default mode | `Error: msg` at the given location | 1 |

- `-debugger` (or `Build_Options_During_Compile.interactive_bytecode_debugger = true`, 0.2.001) stops in the bytecode
  debugger when compile-time code crashes.
- `#dump` after a procedure header prints that procedure's bytecode during compilation (`Disassembly of 'name' ...`),
  also with `-quiet` (32).
- A file stops at its first error. To check that many snippets are rejected (or to show a list of stale forms, as in
  41), compile each one in its own workspace from a metaprogram: every workspace reports its own error.

## Old compile-time code

| Old | Current | Since |
|---|---|---|
| `#run_and_insert f();` | `#insert #run f();` or `#insert -> string { ... }` | removed 0.0.021 (`->` forms 0.0.061) |
| `#body_text` | generate the body with `#insert -> string` | removed 0.0.015 |
| `running_at_compile_time()` | `#compile_time` | removed 0.1.043 |
| `#run () -> T { ... }()` | `#run -> T { ... }` (both still compile) | 0.0.061 |
| `print("50%%")` in generated code | `print("50\%")`; `%%` means two arguments since 0.2.022 | 0.2.022 |
| returning a union from #run | return plain data (warning since 0.2.023; tagged unions lose the payload) | 0.2.023 |

The errors the old forms produce are listed in example 41.

## Cost and judgement

- Compile-time code runs in the bytecode interpreter: fine for generating code and building tables of thousands of
  entries, slow for heavy numeric work. `compiler_begin_intercept(w, .DO_PERFORMANCE_REPORT_RUNS)` reports total time
  in #run (see build-metaprograms.md).
- Every generated thing is something a reader must reconstruct. If generated output has stabilized, paste it from
  `.build/.added_strings_w*.jai` into the source and delete the generator (the bundle's own advice in how_to/500).
