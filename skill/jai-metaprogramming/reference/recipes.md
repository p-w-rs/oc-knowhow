# Recipes: choosing and combining the tools

Validated on Jai beta 0.2.032. Each recipe names the example that implements it (numbers refer to
`examples/jai/jai-metaprogramming/`) and, where one exists, a real-world project that does the same at scale
(library ids). Read how_to/500 and how_to/999 for the bundle's own warnings against overuse.

## Decide first: does this need metaprogramming?

1. Can a plain procedure, a loop over data, or a struct with a table do it? Then do that.
2. Is the input known at compile time, and does computing it at run time cost something that matters (startup, a hot
   path, binary size)? If not, compute at run time.
3. Will the generated code change when the program changes (new structs, new notes, new data files)? If it would be
   written once and then frozen, generate it once, paste it from `.build/.added_strings_w*.jai` into the source, and
   delete the generator.
4. Pick the smallest tool: constant `#run` < `#insert` in one place < polymorphic procedure with `#modify` < macro with
   Code < `#run` that adds build strings < build metaprogram < plugin < replacement default metaprogram.

## Precomputed tables and constants

- `TABLE :: #run make_table();` for anything up to a few thousand entries (01); a big array returned this way becomes
  a fixed constant array.
- Large or mutable data: fill a `#no_reset` global in a `#run` (03), as long as it holds no pointers.
- Keep dependencies explicit when several `#run`s cooperate (02).

## Embedding and parsing files

- `TEXT :: #run -> string { data, ok := read_entire_file(tprint("%file.txt", #filepath)); assert(ok); return data; };`
  embeds a file (02); parse it in the same `#run` to produce typed tables or declarations (44: an enum generated from
  a list of states, with a compile-time self test that rejects duplicates).
- Use `#filepath` rather than relative paths when the code may be compiled from another working directory or from a
  module.
- Validate inputs with `assert` inside the `#run`: a bad data file then stops the build with a message and a stack
  trace (44).

## Generated declarations

- Members, enum values or whole declarations: `#insert #run gen()` or `#insert -> string { ... }` (20, 44).
- Per-type code from `type_info(T)`: a polymorphic procedure whose body is generated (31, as modules/Soa).
- Declarations that depend on the whole program (all structs with a note, all procedures with `@Command`): a build
  metaprogram collects at TYPECHECKED and adds one string at TYPECHECKED_ALL_WE_CAN into a `#placeholder` (35; how_to
  460). For small cases a `#run` in the program can do it with `get_type_table()` and `add_build_string(text, -1)`
  (23; how_to 470).

## Configuration

- Constants plus `#if` for features (06); `#if OS == ...` for platforms.
- Module parameters for library options, one copy per configuration (37); program parameters for whole-program
  switches such as Basic's `ENABLE_ASSERT`.
- Build variants from one build.jai with `- release` arguments and per-workspace Build_Options; hand values to the
  program as generated declarations (38).

## Generic code

- `$T` with the most specific pattern (09), value bakes for sizes and flags (10), polymorphic structs (12),
  restrictions for readable errors and overloads (13), `#modify` to normalize or reject types and to cut the number
  of compiled copies (15, 16).
- Measure compile-time cost with `.DO_PERFORMANCE_REPORT_POLYMORPHS` before optimizing it.

## Custom iteration

- for_expansion on your container (26), named iterators for alternative orders or filters, `#assert` on unsupported
  flags (27), `#insert (break = ..., remove = ...)` when you have nested loops or support `remove`. Bundled models:
  Hash_Table, Bucket_Array, Bit_Array, Xar, Soa.

## Syntax-aware helpers

- An assert or log macro that prints its own expression (`#caller_code`, 22); labelled value dumps (`$args: ..Code`,
  22; modules/Print_Vars `print_vars`); code transformations on a Code argument (21).
- Error-propagation helpers: a macro with `` `return `` turns `x, ok := f(); if !ok return ...;` into one call (24).
- Scope tracing and profiling: a macro with `` `defer `` and `#procedure_name()` (24); `#this` inside a macro is the
  caller.

## Serialization, printing, editors

- Run-time walk over Type_Info (30): one procedure, any type, notes for options. Real-world: `jaison-source`
  (`@JsonIgnore`, `@JsonName(x)`, typed and generic JSON).
- Generated per-type code (31) when speed matters or type info should not ship (32 to shrink what ships).
- Tagged unions (08) can be serialized through `tagged_union_bindings`, but cannot cross from `#run` (03).

## Whole-program checks (house rules)

- A build metaprogram that walks TYPECHECKED bodies and reports with `compiler_report` (34: warning at calls to
  `@Legacy` procedures; 36: naming and float-equality rules that fail the build). Remember the reporting modes
  (CONTINUABLE alone does not fail) and forward messages to Check so print checks stay on (33).
- Ship it as a plugin if several projects want it (40), so `jai main.jai +House_Rules` adds the checks without a
  build file.

## Instrumentation

- Insert calls into procedures tagged `@Trace` with `compiler_modify_procedure` (39); modules/Iprof is the bundled
  instrumenting profiler (a plugin).
- The Rewrite plugin shows the same machinery used for source migration (`+Rewrite`, dry run by default).

## Compile-time tests

- `#assert #run self_test();` runs tests during every build; a failing `assert` stops the build with a stack trace
  (44).
- Real-world: `stubborn-source` is a test runner built as a metaprogram. It loads `*.spec.jai` files with
  `add_build_string`, collects procedures carrying `@Test` notes at TYPECHECKED, generates the calls (with
  parameterized `*_params` arrays) at TYPECHECKED_ALL_WE_CAN, and reports failed expectations with `compiler_report` at
  the assertion's location. `uniform-regex-source` uses it for its test suite.
- Checking that code is REJECTED: compile each snippet in its own workspace and expect one error per workspace (41).

## Small languages (DSLs)

- Put the DSL in a `#string`, parse it in a compile-time procedure, validate it with `assert` (the error points at the
  bad line of the DSL), and `#insert` the generated Jai (45: a state machine compiled to enums and a switch).
- Keep the generated code readable: it is what you debug (`.build/.added_strings_w*.jai`).

## Build systems

- One build.jai next to the sources: debug/release from `- args` (38), several products from one run (38), version
  gating with `compiler_get_version_info` (`focus-editor-source` refuses to build with a too-old compiler and also
  packages a macOS .app from its metaprogram), plugin support for your own workspaces (build-metaprograms.md).
- Editor integration: `jails-source` (language server) compiles your project with its own plugin and defines
  `JAILS_DIAGNOSTICS_BUILD`; a build.jai can test `#if #exists(JAILS_DIAGNOSTICS_BUILD)` to skip writing output.

## Debugging metaprograms

- Print from `#run` and from the message loop (the output goes to the compiler's stdout); add `-debugger` for crashes in
  compile-time code (exit code 3 otherwise).
- Read `.build/.added_strings_w*.jai` for generated code, render nodes with `print_expression`, dump bytecode with
  `#dump`.
- Reproduce with the smallest compile-time-only file (`#run set_build_options_dc(.{do_output = false});` plus a
  `#run` block).
- Mind the traps listed in SKILL.md "Pitfalls": they are the ones that cost the most time while writing these examples.

## Further reading (library ids)

- Bundle: `jai-how-to` (lessons 095–950), `jai-modules-src` (Compiler, Default_Metaprogram, Metaprogram_Plugins,
  Check, Autorun, Program_Print, Code_Visit, Soa, Print_Vars, Reflection), `jai-examples-src` (output_types,
  add_build_string_into_specific_scope, import_replacement, dll, self_inspect, code_type, module_info),
  `jai-changelog` (when something changed).
- Outside: `jails-source`, `jai-parser-source`, `jaison-source`, `stubborn-source`, `uniform-regex-source`,
  `focus-editor-source` (GPL: read, don't copy into permissively licensed code), `the-way-to-jai` (metaprogramming
  chapters; dated after §8: check against the old-forms table), `jai-encyclopedia-of-examples` (its Metaprogramming
  page has a struct-of-arrays generator over `type_info(T).members`), `jai-community-wiki` (dated: its Metaprogramming
  code calls `add_build_string` without a workspace and reads `read_entire_file(file_name=...)`).
