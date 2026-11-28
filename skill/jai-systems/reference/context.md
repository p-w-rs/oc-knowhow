# The context (deep dive)

Verified on Jai beta 0.2.032 (macOS arm64, Linux x86-64). Examples: `examples/jai/jai-systems/01`–`07`, `24`.
Sources to read: `how_to/011_context.jai`, `how_to/225_comma_comma.jai`, `modules/Runtime_Support.jai` (`Context_Base`),
`modules/Preload.jai` (`FIRST_ADD_CONTEXT`), `modules/Remap_Context.jai`, `modules/Thread/primitives.jai`
(`thread_init`). Library: `library_search query="push_context" sources=["jai-how-to","jai-modules-src"]`.

## What it is

- One struct, passed implicitly as a hidden pointer argument to every procedure that is not `#c_call` or
  `#no_context`. In debuggers it is the first parameter, named `context` (`total_mass(context=0x..., ps=...)`).
- Its type is `#Context`: first `base: Context_Base` (added with `#as using`, so a `#Context` converts to
  `Context_Base`), then every `#add_context` field of the whole program in the order the compiler finalizes them.
  Basic adds `print_style` (default formatting of print). Measured: `size_of(Context_Base)` = 96,
  `size_of(#Context)` = 4096.
- `Context_Base` fields (0.2.032, `modules/Runtime_Support.jai`):

| Field | Meaning |
|---|---|
| `context_info: *Type_Info_Struct` | always `type_info(#Context)` of the program that built it (Remap_Context uses it) |
| `thread_index: u32` | 0 on the main thread, 1, 2, ... for `Thread`s, `0xFFFF_FFFF` in a context from `push_context {}` |
| `allocator: Allocator` | used by `alloc`, `New`, `sprint`, `[..]` growth (first growth), ... |
| `logger`, `logger_data`, `log_source_identifier`, `log_level` | used by `log`, `log_error` and modules |
| `temporary_storage: *Temporary_Storage` | per-thread scratch; null in a default-pushed context |
| `stack_trace: *Stack_Trace_Node` | linked list of the current call chain; never null after push_context (sentinel) |
| `assertion_failed`, `handling_assertion_failure` | assert handler and its re-entry guard |
| `default_allocator :: Allocator.{runtime_support_default_allocator_proc, null}` | a constant, not storage |

- The whole `#Context` is padded to `Build_Options.context_size_max` (default 4096 since 0.2.001) because the
  compiler may add fields while compiling. A program whose fields don't fit fails with
  "The #Context has gotten bigger than the limit. The maximum size configured in Build_Options is 4096 bytes, but this
  declaration would make it 8520 bytes." Fix: `jai f.jai -context_size 16384` (Default_Metaprogram accepts up to
  0x40000) or `context_size_max` in a build.jai. Keep big data out of the context: store a pointer.

## Changing it

- Assignment `context.x = v;` writes into the current context. It is **not** undone at the end of the block, and a
  callee that assigns changes what its caller sees afterwards (example 02 prints 10 after the block and 11 after a
  callee incremented it). how_to/011 suggests this can even be used on purpose to pass information up.
- `push_context c { ... }` installs `c` (usually `c := context;` then edits) for the block and restores the previous
  one at the closing brace, also when leaving with `break`, `continue` or `return` (fixed in old betas).
  `push_context,defer_pop c;` (statement form) keeps it until the end of the enclosing scope.
- `push_context { }` with no argument pushes a fresh default context: default heap allocator, default logger,
  `thread_index = 0xFFFF_FFFF`, `temporary_storage = null`, all `#add_context` fields at their initializers.
  With no temporary storage, `tprint` and `temp` fall back to `context.allocator` (the heap): memory you will never
  reset. Use it only where nothing better exists.
- Call-site override `f(args,, field = value, other = v2)` (since 0.1.080; how_to/225): sets the context fields before
  the call and restores them after it. A bare Allocator after `,,` means `allocator =`: `New(Node,, temp)`,
  `copy_string(s,, a)`, `free(p,, a)`. This replaced the explicit `allocator` parameters older code passed.
- Basic's `push_allocator(a)` / `push_allocator(proc, data)` are macros that set `context.allocator` and restore it
  with a `defer` in the **caller's** scope.
- Struct literals: `push_context .{allocator = temp} { }` works (since 0.2.001 a literal is copied). **0.2.032 bug:**
  a literal that names only `#add_context` fields (`push_context .{retries = 3} {}`) can fail with "'retries' is not a
  member of Context0" depending on declaration order: it failed when a zero-argument procedure was declared before
  `main`, or when a second procedure used the same literal; it compiled in other files. Copy-edit-push, `,,`, or a
  literal that also names a `Context_Base` field (`.{allocator = temp, retries = 3}`) always worked (example 04).

## #add_context

- `#add_context name: T = init;` or `#add_context name := init;` at file scope in any file or module. Each field gets
  its initializer wherever a fresh `#Context` is created (program start, `push_context {}`, `c: #Context;`, new
  threads). A duplicate name is a compile error ("Redeclaration of 'level'." with an Info line pointing at the first
  declaration; checked within one program, and how_to/011 says the same across modules). A module can add fields (Iprof adds `_Iprof` and
  `already_inside_profiler_runtime`; the memory debugger adds `inside_memory_debugger`).
- Uses: per-call-tree configuration (indentation, verbosity, current request, current arena), and per-thread state
  without TLS (each thread runs with its own context copy).
- `#exists(context.field)` (since 0.2.015) is **unreliable for `#add_context` fields in 0.2.032**: it is answered
  whenever the compiler reaches it, possibly before the fields are added. Measured, deterministic: as a file-scope
  constant it said `false` for an existing field of the program and even for Basic's `print_style` (`true` for
  `allocator`); inside `main` it said `true` in one program and `false` in another. Don't build logic on it.

## No context: #c_call and #no_context

- `#c_call`: C calling convention (for callbacks registered with C libraries and exported functions); implies no
  context. `#no_context`: Jai calling convention without the hidden pointer (cheap leaf procedures, procedures callable
  from both worlds).
- Calling a context-using procedure from them is a compile error: "Cannot call into a native procedure, from a
  #c_call procedure, without using push_context (because #c_call implies #no_context)." (example 06).
- Inside, either push a default context (`push_context { }`) or a saved one. Pattern for C callbacks with a user-data
  pointer: keep a `#Context` alive somewhere (a global, the object you registered), pass its address as user data,
  and `push_context (cast(*#Context) user).* { ... }` (example 05). The saved context's temporary storage and
  allocator are then the real ones.
- Runtime checks still report inside `#c_call` code without a pushed context (since 0.1.058; verified: a bounds
  failure there prints the usual "Array bounds check failed ..." and "Panic."); the low-level printers in
  Runtime_Support (`write_string`, `write_number`) are `#no_context` and usable there.

## Threads

- `thread_init` stores a `starting_context` in the `Thread`: a default `#Context` into which it copies **only**
  `allocator`, `logger`, `logger_data` and `assertion_failed` from the creating thread, plus a fresh temporary storage
  (`temporary_storage_size`, default 16384 bytes, allocated from the creator's allocator) and the stack-trace sentinel.
  The thread entry sets `thread_index` and pushes it. Everything else, including every `#add_context` field, starts at
  its initializer (example 24: `log_prefix=""` in the thread although main set `"[server] "`).
- Propagate fields with the global hook `thread_init_handler: #type (thread: *Thread)` (0.2.019), called at the end of
  each `thread_init` on the creating thread:
  `thread_init_handler = (t: *Thread) { t.starting_context.log_prefix = context.log_prefix; };`
  Thread_Group workers go through `thread_init` too, so the hook covers them. It is a single global: chain manually if
  several systems need it.

## Across DLLs and static libraries

- A library compiled separately has its own `#Context` layout. `modules/Remap_Context.jai`: `remap_context()`
  returns a context of this program's type, copying members with the same name and size from the caller's
  context (found through `context_info`); `Remap_Context()` (macro) does `push_context,defer_pop remap_context();`.
  Put it first in every exported entry point. `VERBOSE` is a **module** parameter: `#import "Remap_Context"(VERBOSE=false);`
  (`()(VERBOSE=false)` fails: "Too many program parameters: Wanted 0, got 1."). Bundle example: `examples/dll/`.

## Logging through the context

- `log(format, args, flags = .NONE)` / `log_error(...)` build the message with print into temp memory and call
  `context.logger(message, context.logger_data, info)`. `Log_Info` carries `location`, `common_flags` (ERROR, WARNING,
  VERBOSE_ONLY, ...), `user_flags`, `section`, `source_identifier`. The default logger writes to stdout, or stderr when
  `.ERROR` is set, adding a newline if missing. Swap it for a call tree to capture library output (example 07); the
  message string is temporary, so copy it if you keep it. More in how_to/350_logging.jai.

## Old code

| Old | Current |
|---|---|
| `Context` type name | `#Context` (since 0.1.096; `Context` removed 0.2.002: "Undeclared identifier 'Context'.") |
| `f(x, allocator = a)` | `f(x,, a)` / `f(x,, allocator = a)` (0.1.080) |
| `push_context my_default_context {}` | `push_context {}` (0.2.001) |
| `thread_uninit`, `thread_create` | `thread_deinit`, `thread_init` on your own `Thread` |
