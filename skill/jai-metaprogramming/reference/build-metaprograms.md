# Build metaprograms in depth (workspaces, Build_Options, messages, plugins)

Validated on Jai beta 0.2.032 on macOS arm64 and Linux x86-64. Examples 33–43 in `examples/jai/jai-metaprogramming/`
are complete build.jai/main.jai folders. Lessons: how_to/400 (workspaces), 420 (command line), 450 (message loop),
460 (browse and generate), 470 (hooks in the target), 480 (custom checks), 490 (browse by module), 495 (default
metaprogram; its `-plug` text is stale), 380 (module parameters). Bundle programs worth running:
`examples/output_types/build.jai`, `examples/add_build_string_into_specific_scope/build.jai`,
`examples/import_replacement/example.jai`, `examples/dll/build.jai` (library id `jai-examples-src`). Every name below
is declared in `modules/Compiler/Compiler.jai` (`jai-modules-src`); "(not probed)" marks things only read there.

## The shape of every build metaprogram

```jai
#import "Basic";
#import "Compiler";
Check :: #import "Check";                 // optional, see "Keep the default checks"

build :: () {
    set_build_options_dc(.{do_output = false});            // 1. this (metaprogram) workspace writes nothing
    w := compiler_create_workspace("App");                 // 2. a new, isolated program
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);   // 3. inherit -quiet, checks, backend...
    options.output_executable_name = "app";
    set_build_options(options, w);                         // 4. BEFORE any source is added
    compiler_begin_intercept(w);                           // 5. BEFORE any source is added (only if you want messages)
    add_build_file("main.jai", w);                         // 6. compilation of w starts now, in parallel
    while true {                                           // 7. the message loop
        message := compiler_wait_for_message();
        Check.do_error_checking(null, message);
        if message.kind == .COMPLETE break;
    }
    compiler_end_intercept(w);
}
#run build();          // use #run,stallable if the build waits on placeholders (init_plugins does)
```
- Step 1 missing: "No program entry point was found" (build.jai has no `main`).
- Step 3 missing: a fresh workspace has `text_output_flags = OUTPUT_LINK_LINE | OUTPUT_TIMING_INFO`, so the child
  prints "Running linker: ..." and "Stats for Workspace N" even under `-quiet`.
- Without intercept, the loop is unnecessary: workspaces compile on their own and the compiler exits when all are
  done (38-style builds can skip the loop entirely; how_to/400 does).
- `set_build_options` after source was added is illegal; `set_build_options_dc` (`Build_Options_During_Compile`) is
  allowed until PRE_WRITE_EXECUTABLE but covers few fields (below).
- Relative paths given to `add_build_file`, `set_build_options` (import_path) resolve against the folder of the
  **calling file**, which is fine for build.jai next to the sources and wrong for a metaprogram kept elsewhere (42).
- `-` arguments: `jai build.jai - release name=x` → `get_build_options().compile_time_command_line == ["release",
  "name=x"]` (38). Old code used `--`, which now means compiler developer options ("Unknown developer option
  'release'. Use '-- help' for help."). `get_toplevel_command_line()` returns the raw full command line.

## Build_Options (0.2.032; defaults read back from a fresh workspace)

| Field | Default | Notes |
|---|---|---|
| `output_type` | EXECUTABLE | NO_OUTPUT, EXECUTABLE, DYNAMIC_LIBRARY, STATIC_LIBRARY, OBJECT_FILE (38) |
| `output_executable_name` | "" (Default_Metaprogram: first file's basename) | no extension; extension added unless `append_executable_filename_extension = false` |
| `output_path` | "" in a new workspace (Default_Metaprogram: first file's folder) | set it (absolute) when other tools must find the output: Autorun failed to launch a program built with an empty output_path |
| `intermediate_path` | ".build" | objects and `.added_strings_w<N>.jai`; relative to the calling file's folder |
| `entry_point_name` | "" (main) | (not probed) |
| `compile_time_command_line` | user args after `-` | read it from `get_build_options()` (the metaprogram's own options) |
| `import_path` | ["<first file's folder>/modules", "<jai>/modules/"] | searched in order, first match wins for every importer (a local copy of Hash also replaces the one the bundled Hash_Table imports). `-import_dir DIR` entries go in FRONT, in command-line order. Prepend your own folders in a build.jai (verified; relative entries resolve against build.jai's folder) |
| `additional_linker_arguments` | [] | extra linker flags; `set_build_options_dc(.{append_linker_arguments = ...})` from inside a program |
| `use_custom_link_command` | false | then handle READY_FOR_CUSTOM_LINK_COMMAND and call `compiler_custom_link_command_is_complete` (not probed; the bundle's compile_me example of this fails to link on macOS) |
| `temporary_storage_size` | 32768 | |
| `user_data_u64/_string/_pointer` | empty | pass data to code running in that workspace (not probed) |
| `os_target`, `cpu_target` | host | cross-compiling: see the `jai-modules` skill and how_to/950 |
| `backend` | LLVM | `.X64` (or `-x64`) for the fast debug backend |
| `array_bounds_check` | ON | OFF, ON, ALWAYS |
| `cast_bounds_check` | FATAL | OFF, NONFATAL, FATAL |
| `null_pointer_check` | ON | |
| `arithmetic_overflow_check` | OFF | NONFATAL, FATAL |
| `dead_code_elimination` | MODULES_ONLY | NONE (`-no_dce`), ALL |
| `stack_trace` | true | `-o` turns it off |
| `emit_debug_info` | DEFAULT | NONE, DWARF, CODEVIEW |
| `text_output_flags` | OUTPUT_LINK_LINE, OUTPUT_TIMING_INFO | `-quiet` sets 0 |
| `write_added_strings` | true | the `.added_strings` files |
| `interactive_bytecode_debugger` | false | `-debugger` |
| `debug_for_expansions` | false | `-debug_for` |
| `enable_bytecode_inliner` | true | `-no_inline` |
| `prevent_compile_time_calls_from_runtime` | false | make calls to #compiler procedures from run-time code a compile error |
| `maximum_polymorph_depth` | 100 | |
| `maximum_array_count_before_compile_time_returns_are_not_reflected_in_ast` | 5000 | big #run arrays |
| `context_size_max` | 4096 | `-context_size` |
| `runtime_support_definitions` | AUTO | ONLY_INIT / OMIT for libraries linked into non-Jai programs (not probed) |
| `llvm_options`, `x64_options` | | `set_optimization` fills these |
| `info_flags` | 0 | POLYMORPH_MATCH, POLYMORPH_DEDUPLICATE diagnostics (not probed) |

- Everything from `write_added_strings` down to `llvm_options` lives in the `Commonly_Propagated` sub-struct that
  `copy_commonly_propagated_fields` copies (names, paths, output type and import_path are not copied).
- `set_optimization(*options, kind, preserve_debug_info := true)`: `.DEBUG`/`.VERY_DEBUG` keep the checks ON and LLVM
  at O0; `.OPTIMIZED` (O2), `.VERY_OPTIMIZED` (O3, aggressive), `.OPTIMIZED_SMALL` (Os), `.OPTIMIZED_VERY_SMALL` (Oz)
  turn bounds, cast and null checks OFF and enable LLVM inlining (verified for VERY_OPTIMIZED). Command line: `-o`
  (VERY_OPTIMIZED, no stack traces), `-od` (OPTIMIZED), `-very_debug`; `-release` still works with a deprecation
  warning (since 0.2.026).
- `Build_Options_During_Compile` (`set_build_options_dc`): `do_output`, `write_added_strings`,
  `append_executable_filename_extension`, `interactive_bytecode_debugger`, `append_linker_arguments`,
  `output_executable_name`, `output_path`. Usable from a plain program's #run, too.
- Old names: `Build_Options.optimization_level` / `set_optimization_level()` → `set_optimization` (0.1.061);
  `set_output_executable_name()` → `set_build_options_dc(.{output_executable_name = ...})` (0.1.020);
  `modules_search_path_array` → `import_path`; `machine_type` → `cpu_target`; `minimum_macos_version` →
  `minimum_os_version`.

## Messages

`compiler_wait_for_message()` returns a `*Message` (`kind`, `workspace`); cast to the specific struct by kind.

| kind | struct | contents |
|---|---|---|
| FILE | Message_File | `fully_pathed_filename`, `enclosing_import`, `from_a_string`; arrives before any node from that file |
| IMPORT | Message_Import | `module_name` ("" for the main program), `module_type` (PRELOAD, RUNTIME_SUPPORT, MAIN_PROGRAM, FILE), `fully_pathed_filename` |
| FAILED_IMPORT | Message_Failed_Import | `host_module_name`, `target_module_name`, `status` (BLOCKED, NOT_FOUND); answer with `provide_import` (bundle example import_replacement) |
| PHASE | Message_Phase | `phase` (below); `executable_name`, `executable_write_failed`, `linker_exit_code` at POST_WRITE_EXECUTABLE; `num_items_waiting_to_typecheck` at TYPECHECKED_ALL_WE_CAN; object/library lists for custom linking |
| TYPECHECKED | Message_Typechecked | `declarations` (top level), `procedure_headers`, `procedure_bodies`, `structs` (also nested), `others`, `all`; each entry `{expression, subexpressions}` |
| COMPLETE | Message_Complete | `error_code` (NONE, COMPILATION_FAILED, COMPILER_SHUTDOWN); one per intercepted workspace |
| DEBUG_DUMP | Message_Debug_Dump | `dump_text` (not probed) |
| ERROR | Message | (not probed) |
| PERFORMANCE_REPORT | Message_Performance_Report | only with `.DO_PERFORMANCE_REPORT_POLYMORPHS` / `_RUNS`: `time_report.run_directives`, `polymorph_report.records` (`source`, `num_call_sites`, `distinct_polymorphs`), `bytecode_report` |

Phases in order: ALL_SOURCE_CODE_PARSED (repeats as code is added), TYPECHECKED_ALL_WE_CAN (can repeat when you add
code), ALL_TARGET_CODE_BUILT, PRE_WRITE_EXECUTABLE, POST_WRITE_EXECUTABLE, READY_FOR_CUSTOM_LINK_COMMAND (custom link
only). Message order between kinds and files varies from run to run: collect, sort, then print (33).

Intercept_Flags for `compiler_begin_intercept(w, flags)`: SKIP_EXPRESSIONS_WITHOUT_NOTES (only items with notes
arrive; 35), SKIP_DECLARATIONS, SKIP_PROCEDURE_HEADERS, SKIP_PROCEDURE_BODIES, SKIP_STRUCTS, SKIP_OTHERS, SKIP_ALL,
DO_PERFORMANCE_REPORT_POLYMORPHS, DO_PERFORMANCE_REPORT_RUNS. Old names: SKIP_DECLARATIONS_WITHOUT_NOTES (0.0.073),
DO_POLYMORPH_REPORT (0.1.069), message kind COMPILATION_PHASE (alias removed 0.2.009), Message_Compilation_Phase,
phase ALL_SOURCE_CODE_THAT_CAN_CURRENTLY_BE_INFERRED_IS_INFERRED (0.0.046): all undeclared now (41).

## Inspecting typechecked code (34–36)

- Filter to your program: `node.enclosing_load && node.enclosing_load.enclosing_import &&
  node.enclosing_load.enclosing_import.module_type == .MAIN_PROGRAM`.
- Procedure headers: `name` ("" for #run bodies and lambdas), `arguments`/`returns` (Code_Declaration with `name`,
  `type`, `type_inst`), `procedure_flags` (skip POLYMORPHIC and MACRO headers unless you mean them), `notes`. Note that
  `type_to_string(header.type)` prints `procedure (s64, s64) -> s64` without argument names and varargs as `[] T`; 34
  builds a readable signature from `arguments` and `type_inst.inst_flags & .VARARGS`.
- Bodies: walk `subexpressions` (flattened). For calls, `call.resolved_procedure_expression` is the chosen
  procedure (after overloads and polymorphs), so notes on the callee are visible at the call site (34).
- Since 0.2.016 macro and polymorphic bodies also pass through the message pipe before they are used.
- Message data is owned by the compiler; copy strings you keep (`copy_string`), as the examples do.

## Reporting errors and warnings (36)

`compiler_report(message, loc := #caller_location, mode := .ERROR)`; `make_location(node)` turns a node into a
location; `compiler_report(filename, line, column, text, mode)` is the manual overload.

| mode | prints | exit code / executable (0.2.032) |
|---|---|---|
| `.ERROR` (default) | `file:l,c: Error: ...` + excerpt | stops at once; exit 1; later findings never reported |
| `.ERROR_CONTINUABLE` | same text | **exit 0 and the executable is written** unless something else fails |
| `.WARNING` / `.INFO` | `Warning:` / `Info:` | exit 0 |
| `compiler_set_workspace_status(.FAILED, w)` | nothing | exit 1, but the executable is still written |

- Pattern: CONTINUABLE per finding, count them, and at PRE_WRITE_EXECUTABLE raise one `.ERROR` (36: exit 1, no
  executable, every finding shown).
- The header of the report names the **metaprogram's** workspace ("In Workspace 2 ("Target Program")" for a build.jai
  run by the default metaprogram), even when the node belongs to your workspace.
- `compiler_report_error` (removed 0.0.039) was the old name.

## Keep the default checks

The default metaprogram runs the Check plugin (print-format argument checks, binding checks) on the workspace it
creates. Workspaces you create are not checked: `print("% and %\n", 1)` compiled and printed "Invalid % index 2 ..."
at run time. Forward messages yourself, `Check :: #import "Check";` then `Check.do_error_checking(null, message);` in
the loop (33): the compile error comes back ("Incorrect number of arguments supplied to 'print'").

## Generating and changing code

- `add_build_string(text, w)` adds source to workspace w (`-1` = the current one); the overloads taking a Code or a
  Message choose the scope (bundle example add_build_string_into_specific_scope). `add_build_file(path, w)`.
  Without the workspace argument: "Procedure call did not match any of the possible overloads" (the community wiki's
  Metaprogramming page still shows that form).
- Generate after collecting: the first TYPECHECKED_ALL_WE_CAN is the usual moment; the target declares what it waits
  for with `#placeholder` (35). Guard against repeats with a flag.
- `compiler_modify_procedure(w, body)` resubmits an edited body (39); the body comes back marked
  `body_flags.ALREADY_MODIFIED`. The changelog calls this API one the author is unsure about keeping (0.2.016).
- Also available (not probed here): `remap_import`, `provide_import` (bundle example import_replacement),
  `compiler_add_library_search_directory`, `add_global_data` / `add_data_segment` (bundle example add_data_segment),
  `compiler_make_procedure_live`, `compiler_get_struct_location`, `compiler_report_errors_for_unresolved_identifiers`,
  `compiler_set_type_info_flags` (verified in 32), `get_type_table()` (verified), `compiler_get_version_info`
  (verified), `compiler_get_base_path`.

## Module and program parameters (37)

- In the module: `#module_parameters (A := default, B := default) (P := default);`. The first list is per import, the
  optional second list is program-wide. Inside the module they are constants (`#if A`), invisible to importers.
- Import: `#import "M"(A = x);`, `#import "M"()(P = y);` (the empty first list is required), `#import "M";`.
- Each distinct written list compiles a separate copy of the module (separate globals and procedures); identical
  lists deduplicate, the same values in another order do not. Program parameters may be supplied once per program
  ("Cannot supply program parameters for the same module twice"). Unknown names: "Argument name 'X' (number 1) is
  not found in the module parameters."
- Bundled program parameters: Basic's `ENABLE_ASSERT`, `MEMORY_DEBUGGER`, `TEMP_ALLOCATOR_OVERWRITE_MEMORY`,
  `MEMORY_DEBUGGER_REPORT_ASSERTS`; Check's `CHECK_BINDINGS` (module parameter).

## Plugins (40, 43)

- `jai main.jai -quiet +Name opt... +Other opt...`: each `+Name` imports module Name in the metaprogram workspace and
  calls its `get_plugin()`. Arguments up to the next `+` (or a lone `-`) go to that plugin's `init`. Plugins come after
  ordinary flags. Before 0.2.012 this was `-plug Name` (now "Unknown argument '-plug'.", 43) and plugins received
  every argument through `handle_one_argument` (now "'handle_one_argument' is not a member of Metaprogram_Plugin.").
- Hooks of `Metaprogram_Plugin`: `init(p, options: [] string) -> bool`, `before_intercept(p, *Intercept_Flags)`
  (adjust flags; don't add source yet), `add_source(p)` (add initial source; options are final), `message(p, message)`
  (every message of the workspace), `finish(p)`, `shutdown(p)`, `log_help(p)` (printed with `-help`),
  `communication_proc(p, key, value) -> bool` (string channel for compile-time code; not probed). `p.workspace` is the
  workspace being compiled. Embed it in your own struct with `#as using base: Metaprogram_Plugin;`.
- Lookup: plugins are imported by the metaprogram's workspace (workspace 1), whose search path is `modules/` next to
  the first file plus the compiler's `modules/`. `-import_dir` belongs to the target workspace and does not reach it
  ("Unable to find a module called 'Note_Counter'"); the compiler developer option does:
  `jai main.jai +Note_Counter --- import_dir myplugins` (searched before that `modules/`, verified). Conversely
  `--- import_dir` does not change the target workspace's import_path.
- A failing `init` prints "A plugin init() failed. Exiting." and the compiler **exits 0**: check output, not only the
  exit code, in CI.
- Command-line plugins attach to the workspace that Default_Metaprogram created. For `jai build.jai +Autorun` that
  is build.jai's own (NO_OUTPUT) workspace ("[Autorun] Not running anything, because the Build_Options.output_type of
  Workspace 2 is NO_OUTPUT."). To run plugins on your workspaces, do what Default_Metaprogram does (verified):
  ```jai
  #import "Metaprogram_Plugins";
  build :: () {
      ...                                    // create w, set options (with an absolute output_path for Autorun)
      ok, to_create, rest := parse_plugin_arguments(get_build_options().compile_time_command_line);
      plugins: [..] *Metaprogram_Plugin;
      if !init_plugins(to_create, *plugins, w) { compiler_report("plugin init failed"); return; }
      flags: Intercept_Flags;
      for p: plugins  if p.before_intercept  p.before_intercept(p, *flags);   // hooks are optional (may be null)
      compiler_begin_intercept(w, flags);
      for p: plugins  if p.add_source  p.add_source(p);
      add_build_file("main.jai", w);
      // in the loop, for each message:  for p: plugins  if p.message  p.message(p, message);
      // after COMPLETE: call finish, then shutdown, on every plugin that set them
  }
  #run,stallable build();      // plain #run stalls: init_plugins waits for a placeholder it fills itself
  ```
  and run `jai build.jai - +Autorun` (plugins after the lone `-`).
- Bundled plugin modules: Check, Autorun, Program_Print, Codex, Iprof, Rewrite (`jai prog.jai -no_dce +Rewrite` lists
  the `<<` rewrites, `+Rewrite -write` applies them), Performance_Report, Icon, linux_build, Android toolchain;
  `modules/Example_Plugin.jai` is a template. Real-world: `jails-source`'s `metaprogram/jails_diagnostics.jai` adds
  `JAILS_DIAGNOSTICS_BUILD :: true;` from `add_source`, and projects detect it with
  `#if #exists(JAILS_DIAGNOSTICS_BUILD)` to skip writing output.

## Replacing Default_Metaprogram (42)

- `jai main.jai --- import_dir meta meta My_Meta` runs `meta/My_Meta.jai` as workspace 1. `jai -- help` lists the
  developer options (import_dir, meta, no_jobs, randomize, seed, extra, chaos).
- Your metaprogram gets the arguments before `---` (including flags like `-quiet`, which it must implement itself:
  `options.text_output_flags = 0`), and must name the output, choose `output_path`/`intermediate_path`, absolutize
  file paths (relative ones resolve against the metaprogram's folder), load plugins and Check if wanted, and set
  `set_build_options_dc(.{do_output = false})` for itself.
- `modules/Minimal_Metaprogram.jai` is the smallest starting point; `modules/Default_Metaprogram.jai` is the full one
  (`library_search query="Default_Metaprogram parse_plugin_arguments" sources=["jai-modules-src"]`).

## Version gating and other real-world habits

- Gate on the compiler version in the metaprogram: `v: Version_Info; compiler_get_version_info(*v);` then compare
  `major/minor/micro` against a minimum and `compiler_report` if too old (`focus-editor-source`'s first.jai does this
  with `MIN_COMPILER_VERSION`).
- Keep build logic in one build.jai beside the sources; share helpers with the program through `#load`.
- Print one summary line per product, sorted; avoid printing inside message handlers in CI logs.
