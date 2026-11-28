---
name: jai-metaprogramming
description: Jai compile-time execution and metaprogramming at expert level — #run (constants, side effects and ordering, what may cross into the executable, #no_reset, #compile_time, is_constant), #assert, #if/#ifx, polymorphism ($T, $ and $$ bakes, #bake_arguments, #procedure_of_call, $T/Base, $T/interface and type-list restrictions, #modify), type variants and tagged unions, #symmetric, #this, code as data (#code, Code nodes, #insert, #insert -> string, compiler_get_nodes/compiler_get_code, #caller_code, code_of, #placeholder), macros (#expand, backticks, `return, `defer, hygiene), for_expansion iterators, ,, context changes, reflection (type_info, Type_Info structs, notes, enums, Any, serializers), build metaprograms (workspaces, Build_Options, compiler_begin_intercept message loop, TYPECHECKED inspection, compiler_report checks, add_build_string code generation, compiler_modify_procedure, module parameters, - user arguments, metaprogram plugins with +Name, custom default metaprogram), reading and updating old metaprogramming code, and when not to generate code. Load before writing compile-time code, generics, macros, reflection or a build.jai in Jai.
---

# Jai metaprogramming: compile-time code, generics, macros, reflection, build metaprograms

## Ground truth first

- Validated with Jai **beta 0.2.032** (26 Nov 2026) on macOS arm64 and Linux x86-64 (Arch-based and Ubuntu 26.10).
  Every snippet here comes from one of the 45 examples in `examples/jai/jai-metaprogramming/` (numbers in parentheses,
  e.g. (21)), and all of them pass on the three machines. Jai is a closed beta that changes monthly, and what you
  remember from 2015–2022 talks or old forum code is often wrong (see "Reading older code").
- Installed version: `head -1 ~/jai/current/CHANGELOG.txt`. `jai -version` only prints to a terminal
  (`script -q /dev/null ~/jai/current/bin/jai-macos -version`). From code, with Compiler imported:
  `#run { v: Version_Info; print("%\n", compiler_get_version_info(*v)); }` (also returns major/minor/micro).
- **The bundle is the documentation.** Read it for exact signatures and never guess a procedure, flag, message or
  phase name. `modules/Compiler/Compiler.jai` holds Build_Options, Message_*, the Code_* syntax nodes and every
  compiler_* procedure. `modules/Preload.jai` holds Type_Info_*, `Runtime_Support.jai` holds Context_Base, and
  `Default_Metaprogram.jai` is the command line. The how_to lessons: 095 (#if), 100–180 (polymorphism, #modify,
  variants), 225 (`,,`), 380 (module parameters), 400–497 (workspaces, metaprograms, custom checks, #caller_code), 500–560
  (compile-time execution, constancy, #no_reset), 600 (#insert), 630 (Code nodes), 730 (for_expansion), 935 (type info
  reduction), 950 (cross-compiling, `#run,host`). how_to/495 still says `-plug` (stale: use `+Name`).
- Library sources: `library_search query="compiler_begin_intercept Intercept_Flags" sources=["jai-modules-src"]`,
  `["jai-how-to"]` for lessons, `["jai-changelog"]` for "since when", `["jai-examples-src"]` for bundle programs
  (`examples/output_types`, `add_build_string_into_specific_scope`, `self_inspect.jai`, `code_type.jai`). Until
  they're indexed, grep: `grep -n "^compiler_report\|^add_build_string" ~/jai/current/modules/Compiler/Compiler.jai`.
- Real-world, open-licensed code to read (library ids): `jails-source` (a metaprogram plugin that adds
  `JAILS_DIAGNOSTICS_BUILD :: true;` from add_source, and a build.jai with a message loop), `jai-parser-source` (one
  test input per new syntax form), `jaison-source` (Type_Info-driven JSON with `@JsonIgnore`/`@JsonName(x)` notes),
  `stubborn-source` (compile-time test runner on `@Test` notes), `uniform-regex-source`, `focus-editor-source` (GPL;
  a big build metaprogram that checks the compiler version against `MIN_COMPILER_VERSION`), `the-way-to-jai` (book;
  dated from §9 on). Links: `jai-encyclopedia-of-examples` (current), `jai-community-wiki` (dated: its
  Metaprogramming page calls add_build_string without a workspace).
- Sibling skills: `jai` (core language, toolchain, false friends from C/C++/Odin, modernizing old code, probing the
  compiler), `jai-systems` (context, allocators, temporary storage, performance, profiling, threads, debugging),
  `jai-modules` (bundled modules, writing modules: `#module_parameters` basics and scopes, C interop,
  Bindings_Generator, platforms and cross-compiling with `os_target`/`cpu_target`/`#run,host`). This skill covers what
  runs at compile time and the compiler-as-a-library API.

## Mental model

- Three times: **generation** (#run, #insert, metaprogram code), **compilation**, **run time**. Compile-time code is
  ordinary Jai run by the compiler's bytecode interpreter, with Basic, File, String, Compiler and the rest available.
- The compiler is a library driven by a metaprogram. `jai main.jai` runs `Default_Metaprogram` in workspace 1
  ("First Workspace"), which compiles your file in workspace 2 ("Target Program"). A `build.jai` that creates more
  workspaces is your own metaprogram. Workspaces are isolated programs, each with its own globals, imports,
  Build_Options and output.
- Compilation is a dependency graph, not top to bottom. Two file-scope `#run`s have **no defined order**; if one needs
  the other's side effect, make it read a constant the other produces (02).
- Constancy is explicit: `::` is constant, `:=` never is (even `x := 3`). Most "not constant" errors (#if, #assert, `$`
  bakes) come from that.
- Probe quickly with a compile-time-only file: `#import "Compiler"; #run set_build_options_dc(.{do_output = false});
  #run { print(...); }` with no `main`, compiled with `-quiet`. A file reports only its first error; to see many
  failures at once, compile each snippet in its own workspace (41).

## Directive map (example numbers in parentheses)

| Construct | Meaning |
|---|---|
| `#run expr`, `#run { }`, `#run -> T { }` | execute at compile time; the value becomes a constant (01) |
| `#assert cond "msg";` | compile-time check (04) |
| `#if` / `else #if` / `#if x == { case …; }`, `#ifx` | static choice, no new scope (06) |
| `#compile_time`, `is_constant(e)`, `#no_reset` | "am I compiling?", constancy test, keep a global's compile-time value (02, 01, 03) |
| `$T`, `$x`, `$$x`, `#modify { }` | type variable, value bake, optional bake, adjust/reject a polymorph (09, 10, 15) |
| `#bake_arguments f(a = v)`, `#bake_constants f(T = X)`, `#procedure_of_call f(args)` | partial application, fix type variables, pick a polymorph (10, 09) |
| `$T/Base`, `$T/interface X`, `$T/.[A, B]` | type restrictions (13) |
| `#type,distinct X`, `#type,isa X`, `union kind: E { .A ,, a: T; }` | type variants, tagged unions (17, 08) |
| `#symmetric`, `#this`, `#procedure_name()`, `#location(x)`, `#caller_location`, `#file`, `#line`, `#filepath` | swapped-argument match, self and location constants (19) |
| `#code`, `#code,typed`, `#code,null`, `Code`, `code_of(e)`, `#caller_code` | code as a value (20–22) |
| `#insert x`, `#insert,scope() x`, `#insert -> string { }`, `#insert (break = …) body` | paste code (20, 21, 26) |
| `#placeholder N;`, `#exists(N)` | promised declaration, existence test (23) |
| `#expand`, `` `name ``, `for_expansion`, `For_Flags` | macros, caller-scope access, custom `for` (24, 26) |
| `#add_context f: T;`, `#Context`, `f(x,, field = v)`, `push_context` | context extension and per-call changes (28) |
| `@Note`, `@"text"` | notes for reflection and metaprograms (29, 35) |
| `#type_info_none`, `#type_info_procedures_are_void_pointers`, `#type_info_no_size_complaint`, `#dump` | type-info reduction, bytecode dump (32) |
| `#module_parameters (…) (…)`, `#program_export`, `#deprecated "msg"`, `#specified`, `#complete` | module/program parameters, exports, warnings, strict enums (37, 38, 19) |

## Compile-time execution (deep dive: reference/compile-time.md)

```jai
FIB_30 :: #run fib(30);                                   // any procedure; the result is a constant
PRIMES :: #run -> [..] int { ...; return result; };       // short form; arrives as a constant [8] s64
WROTE  :: #run write_version();                           // side effects allowed (files, printing)
#insert #run tprint("ANSWER :: %;", 6 * 7);               // generate a declaration
#assert size_of(Packet) <= 16 "Packet must stay within 16 bytes";
```
- **What crosses into the executable** (01, 03): numbers, bools, strings, Types, enums, fixed arrays and structs of
  those. `[]`/`[..]` results become fixed `[N]` constants. A pointer into compile-time heap memory produces the warning
  "Returned a pointer literal from compile-time execution that could not be mapped" and crashes if used. **Unions,
  including tagged ones, do not survive**: you get a warning, and in 0.2.032 a tagged union built as `{INT, 42}` arrived
  as `{INT, 0}` (03).
- `print` in #run goes to the compiler's output. The working directory is the first file's folder; `#filepath` is
  the current file's folder (with a trailing slash), so embed files with `tprint("%data.txt", #filepath)` (02, 44).
- Globals set by #run are **reset** when the executable is written. `#no_reset x: T;` keeps them, for plain data only:
  a heap string kept this way crashed at run time. Constant pointers to globals (`P :: *some_global;`) do work.
- `#compile_time` is true inside the interpreter. A procedure marked `#compile_time` emits no machine code. Calling a
  `#compiler` procedure (get_build_options, compiler_create_workspace…) from run-time code compiles but panics with
  "Attempt to call a compile-time procedure at runtime";
  `Build_Options.prevent_compile_time_calls_from_runtime = true` turns that into a compile error.
- `is_constant(expr)` is itself always constant and does not evaluate expr. `#run,host` runs with the host's settings
  while cross-compiling (how_to/950, `jai-modules`); on a native build it behaves like `#run`.
- `#assert cond "message";` — **not** `#assert(cond, "msg")`, which fails with "Comma-separated expressions in an
  impermissible place" (05). A failure prints `Compile-time assertion failed. "message"` (04). #assert may call
  procedures directly, but cannot read locals ("Attempt to use a variable from an outer stack frame").
- `#if` needs a constant ("Condition of #if is not constant.", 07). Its braces open **no scope**, so a branch can
  declare things used later. The losing branch must parse but isn't typechecked. It works in structs, enums and at
  file scope; chain with `else #if`, or switch with `#if x == { case …; }` (0.1.084). `#ifx c then a else b` is the
  expression form; the block form yields its last expression (06).
- Failures: an `assert` failing inside #run prints "Assertion failed", a stack trace, and "There were errors on
  Workspace 2" (exit 1). A crash in compile-time code exits **3** and suggests `-debugger`.

## Polymorphism (deep dive: reference/polymorphism.md)

```jai
largest      :: (items: [] $T) -> T { ... }                // $T defines T once; plain T uses it
append_item  :: (array: *[..] $T, item: T) { ... }         // the array decides T; a wrong `item` is the error
repeat_char  :: (c: u8, $n: int) -> string { buf: [n] u8; ... }        // value bake: callers pass constants
scaled       :: (x: int, $$factor: int) -> int, string { #if is_constant(factor) {...} else {...} }
triple :: #bake_arguments scale(K = 3);      show_u8 :: #bake_constants show(T = u8);
p1 :: #procedure_of_call largest(int.[1]);   // the polymorph a call would use, as a constant
```
- One copy per distinct set of parameters, deduplicated across the program; a #run in the body runs once per copy (09).
  `#dump` on a procedure prints its bytecode at compile time (32). Trailing commas in headers are fine again (0.2.025).
- Make patterns specific (`*[..] $T` rather than `$T`) and put the `$` on the authoritative argument, so errors land at
  the call ("Type mismatch. Type wanted: s64; type given: string."). Defining `$T` twice is an error.
- `-> $R` cannot be solved from a call ("Compile-time variable 'R' is needed but was not specified"); fill it in
  `#modify` (15). A polymorphic procedure has no run-time value ("This declaration is polymorphic…"); bind it to a
  constant or pick a polymorph with #procedure_of_call.
- `$n` needs a constant at every call ("requires a value bake", 11); `$$n` bakes only constants (10).
  **`#bake_constants` fixes only type variables like `$T`**. A value parameter `$K: int` needs `#bake_arguments`
  ("There is no bakeable constant named 'K'. Did you mean #bake_arguments?", 41).
- Structs (12): `Small_Buffer :: struct (T: Type = float, Capacity: int = 8) {...}` takes defaults and named arguments,
  and parameters are members (`b.T`). In a header, the bare `Small_Buffer` matches every instance. `*#this` means a
  pointer to this instance type. Reflection: `specified_parameters`, `polymorph_source_struct.parameters`.
  `Type_Info_Struct.alignment` is **-1 for polymorphic instances** (0.2.032).
- Restrictions (13, 14): `$T/Entity` (Entity or `#as using` it), `$T/interface Has_Size` (duck typing by member names and
  types), `$T/.[string, u8]` (a type list; anything else fails with "did not match any of the possible target types of
  a type restriction"). Restriction targets must be structs or type lists. A failed interface reports "The given type
  does not match the required interface".
- `#modify { …; return true; }` / `return false, "why";` (15, 16) runs after solving. The variables are mutable
  `Type` values: inspect them with `cast(*Type_Info) T`, because `size_of(T)` and `x: T` fail there. Use it to collapse
  types, compute `$R`, validate struct parameters, or allow same-header overloads for disjoint types. A rejection says
  "#modify returned false: why"; an #assert in the body cannot steer overload resolution.
- Type variants (17, 18): `Handle :: #type,distinct u32;` (literals convert, variables need a cast); `Meters ::
  #type,isa float;` (converts toward float; calls returning the base type return the variant). The tag is `.VARIANT`.
  A zero-initialized `Type` is `void` and falsy (0.2.029).
- Tagged unions (08, experimental since 0.2.023): `Shape :: union kind: Shape_Kind { .CIRCLE ,, radius: float; … }`.
  The tag comes first, prints as `{RECT, [3, 4]}`, and literals are `.{.LABEL, "door"}` (two values or none). There are
  no safety checks: switch on the tag yourself. Reflection uses `UNION_IS_TAGGED` and `tagged_union_bindings`.
- `#symmetric` on a two-argument procedure or operator also matches swapped arguments (19).

## Code as data (deep dive: reference/code-nodes.md)

```jai
#insert "x *= 10;";                             // a constant string, parsed as source (statement)
y := 1 + #insert "x;";                          // expression level: one expression, still ends in ;
Rgba :: struct { #insert #run member_list(.["r", "g", "b", "a"], "float"); }
#insert -> string { ...; return text; }         // short form of #insert #run () -> string {...}();
expr :: #code (a + b) * 2;   r := #insert expr;  // Code: unevaluated syntax, resolved where inserted
```
- Inserted text lands in `.build/.added_strings_w<N>.jai`, annotated with the file:line that produced it, and errors in
  generated code point there. Inside a generated `print` format, a literal `%` is `\%`; `%%` now means two arguments.
- `compiler_get_nodes(code) -> root, nodes` gives a **fresh, editable** tree (`nodes` flattened, children first).
  `compiler_get_code(root, code)` turns it back into Code, and `print_expression(*sb, node)` (Program_Print) into source
  (21). Single-character operators are stored as ASCII: `op.operator_type == #char "+"`.
- `code_of(expr)`, `call := #caller_code` and `$args: ..Code` give you the caller's syntax (22). **Code arrives with
  constants already substituted**: `fixed.count` and `LIMIT * 2` show up as plain numbers.
- `#placeholder NAME;` is a promise kept by a #run with `add_build_string(text, -1)` (23) or by a metaprogram (35).
  Unfilled: "Placeholder for identifier 'NAME' was never filled." `#exists(name)` is a constant bool (0.1.091).
- Scope inside a macro: plain `#insert c` resolves where `c` was written (the caller's locals);
  `#insert,scope() c` resolves at the insertion point (macro locals, not the caller's).

## Macros, for_expansion, `,,` (deep dive: reference/macros-and-for-expansions.md)

```jai
make_counter :: () #expand { `counter := 0; }                 // declares in the caller
scope_trace  :: (name: string) #expand { print("enter %\n", name); `defer print("leave %\n", name); }
return_if    :: (failed: bool, v: int) #expand { if failed `return v; }   // returns from the CALLER
timed        :: (n: int, body: Code) #expand { for 1..n #insert body; }
timed(3, #code runs += 1);                                    // no ';' before ')' inside a call
```
- Macros are always inlined and **hygienic** (24, 25). Without a backtick you get "Undeclared identifier 'total'" plus
  "While expanding macro…". Arguments are evaluated once. Inside a macro, `#procedure_name()` and `#this` refer to the
  caller.
- A backticked declaration goes to the caller's scope whatever braces surround it, so emitting `` `i := … `` per
  unrolled copy gives "Redeclaration of 'i'." Declare once and assign per copy (20).
- for_expansion (26): `for_expansion :: (c: *Box, body: Code, flags: For_Flags) #expand`. It must declare `` `it `` and
  `` `it_index ``, then `#insert body;`. Flags `.REVERSE`/`.POINTER` are constants (`for <=REVERSE i: 0..n-1`); reject
  unsupported ones with `#assert` (27). Named iterators look like `for :evens c`, and loop control is rewritten with
  `#insert (break = break outer, remove = {…}, continue = {…}) body;`. Use `-debug_for` to step into expansions.
- `,,` (28): `f(x,, allocator = temp)`, `f(x,, temp)`, `log(…,, logger = my_logger)`, and your own
  `#add_context depth: int;`. It is sugar for `push_context`. The context type is `#Context` (bare `Context` is gone
  since 0.2.002); take `Context_Base` for just the base fields.
- Prefer a procedure unless you need the caller's scope, `` `return ``/`` `defer ``, Code arguments, or constants
  propagated from the call.

## Reflection (deep dive: reference/reflection.md)

- `type_info(T)` returns the most specific struct, e.g. `*Type_Info_Struct`. Every one has a `type` tag and
  `runtime_size`. Structs add `name, members, notes, textual_flags, alignment, parameters, specified_parameters,
  polymorph_source_struct, tagged_union_bindings, constant_storage, initializer`. Members have
  `name, type, offset_in_bytes, flags` (.CONSTANT .USING .AS …) and `notes`. Enums: `names, values, enum_type_flags`.
  Arrays: `array_type, element_type, array_count`. Variants: `variant_of`.
- Notes go after a member's semicolon (`name: string; @Key`), after a procedure body, or after `struct`/`enum`;
  `@"two words"` for text with spaces (29, 30). In metaprograms they are `*Code_Note` with `.text` (34, 35).
- Struct constants appear as members flagged CONSTANT with offset -1, so skip them when serializing.
- Helpers: Basic `enum_names`, `enum_values_as_s64`, `type_to_string`, `get_field`. Reflection
  `enum_name_to_value`, `enum_value_to_name`, `get_enum_value`, `get_array_count_and_data`. Also `initializer_of(T)`,
  and Compiler's `get_type_table()` and `is_subclass_of`.
- `Any` is `{type, value_pointer}`: switch on `a.type.type` and cast `value_pointer` (29).
- Serializers: a run-time Type_Info walk is one procedure for every type (30; `jaison-source` is the real-world
  version), or per-type code generated with `#insert -> string` from `type_info(T)` leaves no walk at run time (31).
- Type info is emitted only for types asked about. Shrink it with `#type_info_none`,
  `#type_info_procedures_are_void_pointers`, `#type_info_no_size_complaint`, or
  `#run compiler_set_type_info_flags(T, .NO_TYPE_INFO)` (32).

## Build metaprograms (deep dive: reference/build-metaprograms.md)

```jai
Check :: #import "Check";
#run {
    set_build_options_dc(.{do_output = false});                       // this workspace writes nothing
    w := compiler_create_workspace("App");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);   // inherit -quiet, checks, backend
    options.output_executable_name = "app";
    set_build_options(options, w);                                    // before adding source
    compiler_begin_intercept(w);                                      // before adding source
    add_build_file("main.jai", w);
    while true {
        message := compiler_wait_for_message();
        Check.do_error_checking(null, message);                       // keep print() checks (see below)
        if message.kind == .TYPECHECKED { tc := cast(*Message_Typechecked) message; /* inspect */ }
        if message.kind == .COMPLETE break;
    }
    compiler_end_intercept(w);
}
```
- Without `do_output = false`: "No program entry point was found". Without `copy_commonly_propagated_fields`, the
  child ignores `-quiet` (it prints the link line and stats).
- **The Check plugin only checks workspaces the default metaprogram creates.** In yours, `print("% %", 1)` compiles
  and misbehaves at run time unless you forward messages to `Check.do_error_checking` (33).
- Messages (33): `.FILE`, `.IMPORT` (module_type MAIN_PROGRAM/FILE/…; the main program's name is ""),
  `.FAILED_IMPORT`, `.PHASE`, `.TYPECHECKED`, `.COMPLETE` (with error_code), `.DEBUG_DUMP`, `.ERROR`,
  `.PERFORMANCE_REPORT`. Phases: ALL_SOURCE_CODE_PARSED, TYPECHECKED_ALL_WE_CAN, ALL_TARGET_CODE_BUILT,
  PRE/POST_WRITE_EXECUTABLE, READY_FOR_CUSTOM_LINK_COMMAND. Arrival order varies, so sort before printing.
- Message_Typechecked: `declarations` (top level only), `procedure_headers`, `procedure_bodies`, `structs` (these three
  include nested ones), `others`, `all`. Each entry is `{expression, subexpressions}`, with subexpressions flattened
  and typed (34). To keep only your own code, check `node.enclosing_load.enclosing_import.module_type == .MAIN_PROGRAM`.
  `.SKIP_EXPRESSIONS_WITHOUT_NOTES` delivers only noted items (35).
- **Reporting** (36): `compiler_report(msg, make_location(node), mode)`. In 0.2.032, `.ERROR` (the default) stops
  immediately. `.ERROR_CONTINUABLE` prints "Error:" but the build still **exits 0 and writes the executable**. `.WARNING`
  and `.INFO` never fail. `compiler_set_workspace_status(.FAILED, w)` exits 1 but still writes the executable. Reliable
  pattern: report CONTINUABLE for each finding, then raise one `.ERROR` at PRE_WRITE_EXECUTABLE.
- Generate code (35): collect at TYPECHECKED, then `add_build_string(text, w)` at the first TYPECHECKED_ALL_WE_CAN
  (it can repeat, so guard with a flag). Rewrite code (39): edit `body.block.statements`, then
  `compiler_modify_procedure(w, body)`, skipping `.ALREADY_MODIFIED`.
- Configurations (38): arguments after a lone `-` arrive in `compile_time_command_line`. `set_optimization(*o, .DEBUG |
  .OPTIMIZED | .VERY_OPTIMIZED …)`. `output_type` is EXECUTABLE, DYNAMIC_LIBRARY, STATIC_LIBRARY, OBJECT_FILE or
  NO_OUTPUT, and the OS extension is added for you. Pass configuration to the program as generated declarations.
- Relative paths in `add_build_file`/`set_build_options` resolve against the **calling file's** folder; absolutize
  them when your metaprogram lives elsewhere (42).

## Module parameters, plugins, custom default metaprogram

- `#module_parameters (LOUD := false) (LOG_CALLS := false);` takes per-import parameters, then program-wide ones.
  Import with `#import "Greeter"(LOUD = true);` and `#import "Greeter"()(LOG_CALLS = true);` (37). Each distinct list is
  a **separate copy** with its own globals. Deduplication happens only when lists are written identically (other order
  = another copy). Program parameters may be set only once. Basic has some: `#import "Basic"()(ENABLE_ASSERT = false);`.
  Writing modules in general (scopes, folders) is `jai-modules` territory.
- `#import` search order (`Build_Options.import_path`, verified): **`-import_dir` folders first** (in command-line
  order; relative ones resolve against the first file's folder), then `modules/` next to the first compiled file, then
  the compiler's `modules/`. The first match wins for every importer, so a local `modules/Hash.jai` also replaces the
  bundled Hash inside the bundled Hash_Table. In a build.jai, put your own folders at the front of
  `options.import_path` (relative entries resolve against build.jai's folder).
- Plugins (40): `jai main.jai +Name opts… +Autorun`, with plugins last. `-plug` fails with "Unknown argument '-plug'."
  (43; changed in 0.2.012). A plugin module defines `get_plugin() -> *Metaprogram_Plugin` with `init(p, options) ->
  bool`, `before_intercept`, `add_source`, `message`, `finish`, `shutdown`, `log_help`. Plugins load in the
  **metaprogram's** workspace, which `-import_dir` does not reach: put them in `modules/` next to the first file, or
  pass the compiler developer option `--- import_dir DIR` (searched before that `modules/`). If init
  fails, the compiler prints "A plugin init() failed. Exiting." and **exits 0**. Bundled plugins: Check (on unless
  `-no_check`), Autorun, Program_Print, Codex, Iprof, Rewrite (+Rewrite migrates `<<`; needs `-no_dce`).
- Command-line plugins attach to the workspace Default_Metaprogram created. With `jai build.jai +Autorun` that is
  build.jai's own NO_OUTPUT workspace, so the plugin never sees yours ("[Autorun] Not running anything, because the
  Build_Options.output_type of Workspace 2 is NO_OUTPUT."). To support plugins in a build.jai, call
  `parse_plugin_arguments` and `init_plugins` (modules/Metaprogram_Plugins), call the hooks yourself, run it with
  `#run,stallable` (a plain `#run` stalls), and pass them after `-`: `jai build.jai - +Autorun`. The verified recipe is
  in reference/build-metaprograms.md.
- Replace Default_Metaprogram with `jai main.jai --- import_dir meta meta My_Meta` (42; `jai -- help` lists the
  developer options). Then argument parsing (including mapping `-quiet` to `text_output_flags = 0`), naming, plugins
  and Check are your job.

## Reading older code (all verified to fail on 0.2.032 in 41 or 43)

| Old | Now | Since |
|---|---|---|
| `#run_and_insert f();`, `#body_text` | `#insert #run f();` / `#insert -> string {…}` | removed 2020 |
| `c: Context;` | `#Context` (or `Context_Base`) | 0.2.002 |
| `running_at_compile_time()` | `#compile_time` | 0.1.043 |
| `compiler_get_command_line_arguments()` | `get_build_options().compile_time_command_line` | 0.1.020 |
| `set_output_executable_name(n)` | `set_build_options_dc(.{output_executable_name = n})` | 0.1.020 |
| `compiler_report_error(m)` | `compiler_report(m, loc, mode)` | 0.0.039 |
| `.COMPILATION_PHASE`, `Message_Compilation_Phase` | `.PHASE`, `Message_Phase` | 0.2.009 / 0.0.046 |
| `.SKIP_DECLARATIONS_WITHOUT_NOTES`, `.DO_POLYMORPH_REPORT` | `.SKIP_EXPRESSIONS_WITHOUT_NOTES`, `.DO_PERFORMANCE_REPORT_POLYMORPHS` | 0.0.073 / 0.1.069 |
| `Build_Options.optimization_level` | `set_optimization(*o, .OPTIMIZED)` | 0.1.061 |
| `Metaprogram_Plugin.handle_one_argument` | `init(p, options) -> bool` | 0.2.012 |
| `Code_Directive_If`, `Code_Size_Or_Type_Info` | `Code_If`, `Code_Type_Query`/`Code_Expression_Query` | 0.1.084 / 0.1.091 |
| `add_build_string(text)` | `add_build_string(text, w)` (-1 = current) | — |
| `-plug Name`, `jai f.jai -- args` | `+Name` last; `jai f.jai - args` | 0.2.012 / 0.1.048 |
| `#import "Tagged_Union"` | `union kind: Kind {…}` | 0.2.025 |
| `print("100%%")` in generated code | `"100\%"` (`%%` = two args since 0.2.022) | 0.2.022 |

## Patterns and judgement (deep dive: reference/recipes.md)

| Need | Tool (example) |
|---|---|
| Precomputed tables, embedded files | `X :: #run make();`, `#no_reset`, `read_entire_file` at compile time (01–03, 44) |
| Declarations from data | `#insert #run gen()` in an enum, struct or file scope (20, 44) |
| Configuration | constants + `#if`; module parameters; build arguments (06, 37, 38) |
| Generic code | `$T` patterns, restrictions, `#modify` (09–16) |
| Custom `for` | for_expansion (26) |
| Syntax-aware helpers | macros with Code, `#caller_code`, `..Code` (21, 22) |
| Serialization, printing | Type_Info walk (30) or generated code (31) |
| Registries, house rules, instrumentation | metaprogram + notes (35), `compiler_report` (34, 36), `compiler_modify_procedure` (39) |
| Compile-time tests, small DSLs | `#assert #run self_test();` (44); parse a `#string` and `#insert` (45) |

- When **not** to: if hand-written code would read the same, write it by hand. Generation adds a third time to reason
  about, new ways to fail and compile time (how_to/500). Once generated code stops changing, paste it from
  `.build/.added_strings_w*.jai` into the source. Prefer a procedure to a macro, and sort what you collect.

## Debugging and teaching

- Print from #run and from the message loop; read `.build/.added_strings_w*.jai`; render Code with `print_expression`;
  use `#dump` and `-debugger`. Exit codes: 0 ok, 1 compile error, 3 compile-time crash. Never pipe the compiler into
  `head` when you need the executable (SIGPIPE killed it: exit 141).
- To explain a feature: a few sentences, a runnable example, then an experiment that breaks it. Remove the backtick in
  (24), move the `$` in (09), make the #modify in (15) reject, write `#assert(c, "m")` (05), delete the placeholder fill
  in (35), or drop the Check forwarding in (33) and pass a bad print. The quoted errors are what the user will see.

## Pitfalls (each verified on 0.2.032)

- `#assert(cond, "msg")` (05); `#if` on a `:=` variable (07); `$n` given a variable (11); `#bake_constants` on a value
  parameter (41).
- Unordered #run side effects (02); pointers or unions in #run results and `#no_reset` data (03); `%%` in generated
  formats; `#code x += 1;` with `;` inside call arguments is a parse error (24).
- `.ERROR_CONTINUABLE` alone doesn't fail the build (36); your own workspaces skip Check (33); plugins aren't found via
  `-import_dir` (use `modules/` or `--- import_dir`) and a failed init exits 0 (40); relative paths in a metaprogram
  follow the calling file (42); an `-import_dir` or local `modules/` copy of a module silently replaces the bundled one
  everywhere, bundled importers included.
- Name clashes with imported modules (String already has `path_filename`) give "Procedure call matches 2 possible
  overloads". `interface` is reserved (0.2.017). Third-party code from before 26 Nov 2026 may use
  `New(T, initialized = …)`, now `initialize`.

## Examples and deep dives

`examples/jai/jai-metaprogramming/` (`cd oc-knowhow && pixi run jai-examples -- --skill jai-metaprogramming`): 01–08
compile time and unions, 09–19 polymorphism, 20–23 code as data, 24–28 macros, iteration, context, 29–32 reflection,
33–43 build metaprograms, plugins and old forms (folders with build.jai or main.jai), 44–45 patterns. Deep dives in this
skill's folder: reference/compile-time.md, reference/polymorphism.md, reference/macros-and-for-expansions.md,
reference/code-nodes.md, reference/build-metaprograms.md (Build_Options fields with defaults, every message and phase,
plugin lifecycle), reference/reflection.md, reference/recipes.md.
