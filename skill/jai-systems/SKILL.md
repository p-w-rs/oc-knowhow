---
name: jai-systems
description: Jai systems programming (beta 0.2.032) — the implicit context (#Context, push_context, the ,, call-site override, push_allocator, #add_context, #c_call/#no_context callbacks, context in threads), allocators (Allocator_Proc modes, alloc/free/New/NewArray, [..] remembering its allocator, Default_Allocator, Flat_Pool, Pool, rpmalloc heaps, Bucket_Array, writing an arena), the memory debugger and leak reports, Overwriting/Unmapping allocators, temporary storage (temp, tprint, reset_temporary_storage, auto_release_temp, marks, overflow pages), build modes with measured costs (debug, -od, -o, x64 vs LLVM, bounds/cast/null/overflow checks, #no_abc, stack traces, inline), data layout (#align, #no_padding pitfall), #asm (x64 only), SIMD, sort and hash costs, timing, profiling (Iprof, Performance_Report, sample/xctrace, callgrind), concurrency (Thread, Thread_Group, Mutex, Semaphore, atomics) and debugging (crash messages, assert handlers, stack traces, lldb/gdb, -debugger), plus updating older memory and context code. Load before writing or reviewing Jai code that manages memory, threads or performance, before debugging or profiling a Jai program, or when porting older Jai code.
---

# Jai systems: context, memory, performance, threads, debugging

## Ground truth first

- Validated with **Jai beta 0.2.032** (26 Nov 2026) on macOS arm64 (M2 Max; LLVM backend only), Linux x86-64
  **powerslabs** (Core Ultra 9 285K, hardened Arch kernel) and **ubuntu-laptop** (Core Ultra 7 265H, Ubuntu 26.10).
  Everything below was compiled and run there; the 40 examples in `oc-knowhow/examples/jai/jai-systems/` pass on all
  three (one is macOS-only by design). Jai is a closed beta that changes monthly: verify, don't trust.
- Your version: `script -q /dev/null ~/jai/current/bin/jai-macos -version` (Linux:
  `script -qc "~/jai/current/bin/jai-linux -version" /dev/null`; it prints only to a terminal). Then read
  `~/jai/current/CHANGELOG.txt` for every version after 0.2.032.
- **Read the module source for exact signatures, never guess.** Library sources (built from `~/jai/current`):
  `jai-how-to`, `jai-modules-src`, `jai-examples-src`, `jai-changelog` ("when did X change?"), e.g.
  `library_search query="auto_release_temp" sources=["jai-modules-src","jai-how-to"]`, then `library_read`. If they
  are not indexed yet: `grep -rn "^thread_init ::" ~/jai/current/modules`. Lessons: `how_to/011_context.jai`,
  `012_temporary_storage.jai`, `200_memory_management.jai`, `225_comma_comma.jai`, `250_how_parameters_are_passed.jai`,
  `350_logging.jai`, `700_stack_trace.jai`, `800_allocators.jai`, `900_inline_assembly.jai` (x64 only: it does not
  build with the arm64 compiler). Bundle demos: `modules/Basic/examples/memory_debugger.jai`,
  `modules/Thread/examples/thread_group.jai`, `modules/{Overwriting,Unmapping}_Allocator/examples/` (crash on purpose).
- Outside the bundle (all older than 0.2.032; check with the table at the end): `the-way-to-jai` (Apache-2.0 book,
  **dated** after §8: still teaches `Context`, `get_time`, `allocator =` parameters), `jaison-source` (Type_Info-driven
  JSON, temp allocator use, leak tests with the memory debugger), `stubborn-source` (compile-time test runner),
  `hyperserve-source` (threads and sockets in a server), links `jai-encyclopedia-of-examples` (current) and
  `jai-community-wiki` (**dated**: bare `Context` in its Advanced page).
- Key files: `modules/Preload.jai` (Allocator, Allocator_Mode, Allocator_Caps, Stack_Trace_Node, atomic intrinsics),
  `modules/Runtime_Support.jai` (Context_Base, Temporary_Storage, runtime-check messages, `debug_break`),
  `modules/Basic/module.jai` (alloc, New, temp, push_allocator, Basic's module parameters),
  `Basic/Temporary_Storage_Paged_Alloc.jai`, `Basic/Memory_Debugger.jai`, `modules/Compiler/Compiler.jai`
  (`Build_Options`, `set_optimization`), `modules/Default_Metaprogram.jai` (what each command-line flag sets).
- Siblings: **jai** (language basics, false friends), **jai-metaprogramming** (#run, build.jai workspaces, plugins,
  #insert), **jai-modules** (Basic, String, Hash_Table, File...). Contrast: **odin-performance** (Odin allocators
  return errors and have Free_All; Jai's return null and use heaps/reset), **c-perf** (Tracy, mimalloc).

## The context

- Every procedure except `#c_call`/`#no_context` ones receives a hidden pointer to the **context** (debuggers show it
  as a `context` parameter). Its type `#Context` is `Context_Base` (96 bytes: `context_info, thread_index: u32,
  allocator, logger, logger_data, log_source_identifier, log_level, temporary_storage, stack_trace, assertion_failed,
  handling_assertion_failure`, plus the constant `default_allocator`) followed by every `#add_context` field of the
  program (Basic adds `print_style`). It is padded to `Build_Options.context_size_max` = 4096 bytes (since 0.2.001);
  grow it with `jai f.jai -context_size 8192`. Old code says `Context` ("Undeclared identifier 'Context'." since
  0.2.002): write `#Context`, or `Context_Base` for parameters that only need allocator/logger (`f(context)` converts).
- Changing it (example 02):

| Form | How long the change lasts |
|---|---|
| `context.x = v;` | until changed again: **not** undone at `}`, and a callee's change is seen by its caller |
| `f(a, b,, x = v)`, `New(T,, temp)` (a bare Allocator after `,,` sets `allocator`) | that one call |
| `push_context c { ... }` (c: a copy of `context`, edited) | the block, also on break/return |
| `push_context,defer_pop c;` | the rest of the enclosing scope |
| `push_allocator(a)` / `push_allocator(proc, data)` (Basic macros) | the rest of the enclosing scope |
| `old := context.x; context.x = v; defer context.x = old;` | the scope, by hand |

- `#add_context name := init;` anywhere (file scope, modules) adds a field: per-call-tree settings and, since every
  thread has its own context, thread-local data without TLS cost (example 03). Same name in two modules = compile error.
- **Bug (0.2.032):** `push_context .{my_field = 3} {...}` whose literal names only `#add_context` fields can fail with
  "'my_field' is not a member of Context0", depending on declaration order (example 04). Use copy-edit-push or `,,`;
  literals that also name a `Context_Base` field (`.{allocator = temp, my_field = 3}`) worked every time.
- `#c_call` (C ABI) and `#no_context` (Jai ABI) procedures have no context: calling `print` there is a compile error
  ("Cannot call into a native procedure, from a #c_call procedure, without using push_context"). Inside,
  `push_context { }` gives a **default** context: default heap, `thread_index = 0xFFFF_FFFF`, **no temporary storage**
  (then `tprint`/`temp` fall back to the heap and leak), #add_context fields at their initializers. Better: pass a
  saved context through the C library's user pointer and `push_context saved.* { }` (example 05, 06).
- `context.logger` / `logger_data` / `log_level`: `log`, `log_error` and modules log through it; swap it around a
  call tree to capture or silence output (example 07). `context.assertion_failed`: see Debugging.
- New threads copy only `allocator, logger, logger_data, assertion_failed`; **#add_context fields restart at their
  initializers**. Copy them in the global hook `thread_init_handler = (t: *Thread) { t.starting_context.f =
  context.f; };` (runs on the creating thread; also for Thread_Group workers; example 24).
- DLL/static-library entry points compiled with a different #Context: `#import "Remap_Context"(VERBOSE=false);`
  (module parameter) and `Remap_Context();` as the first statement (copies fields by name and size).
- deep dive: reference/context.md

## Allocators

```jai
Allocator_Proc :: #type (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void;
Allocator      :: struct { proc: Allocator_Proc; data: *void; }
```
- Modes: `ALLOCATE` (null = out of memory), `RESIZE` (realloc; the caller supplies `old_size`, so simple allocators
  need no size headers), `FREE` (no size), `STARTUP`/`SHUTDOWN`, `THREAD_START`/`THREAD_STOP`, `CREATE_HEAP` (returns
  data for a new heap) / `DESTROY_HEAP` (frees that whole heap), `IS_THIS_YOURS`, `CAPS` (return `Allocator_Caps`:
  `MULTIPLE_THREADS, CREATE_HEAP, FREE, ACTUALLY_RESIZE, IS_THIS_YOURS` + `HINT_I_AM_*`; write a name into
  `(cast(*string) old_memory).*` when non-null). No error codes and no FREE_ALL mode: misuse may assert; bump
  allocators expose their own `reset`. Spec: `how_to/800_allocators.jai`.
- Basic API (through `context.allocator`): `alloc(n)`, `free(p)`, `free(s: string)`, `realloc(p, new_size, old_size)`,
  `New(T)`, `New(T, initialize=false)`, `NewArray(count, T, initialize=true, alignment=-1) -> (array, unaligned_base)`
  (with an alignment, free `unaligned_base`), `copy_string`, `alloc_string`, `sprint` (heap) vs `tprint` (temp),
  `array_reserve`, `array_free`, `array_reset` (frees), `array_reset_keeping_memory`, `create_heap(a)`,
  `destroy_heap(h)`, `get_capabilities(a) -> (caps, name)` (examples 08, 10).
- **No allocator parameters** (removed in 0.1.080): pick the allocator for one call with `,,` —
  `alloc(64,, temp)`, `New(Node,, a)`, `copy_string(s,, allocator = a)`, `free(p,, a)`, `builder_to_string(*b,, temp)`.
  Old `alloc(64, a)` / `copy_string(s, a)` → "Too many arguments: Wanted 1, got 2."; `New(T, allocator = a)` →
  "Argument name 'allocator' (number 2) is not found in the procedure being called."; `free(p, a)` → "Procedure call
  did not match any of the possible overloads." (example 11).
- **0.2.032 renamed `New`/`NewArray`'s `initialized` to `initialize`** with no deprecation period: old code (focus,
  uniform and jai-postgres all hit it this week) fails with "Argument name 'initialized' (number 2) is not found in the
  procedure being called" (example 11).
- `[..] T` (40 bytes: count, data, allocated, allocator) **remembers `context.allocator` at its first growth** and
  keeps using it, even outside the scope that pushed it; `array_free`/`array_reset` use it. `[] T` and `string`
  (16 bytes) carry no allocator: free them with the one that made them (`free(s,, a)`). Hash_Table, String_Builder,
  Bucket_Array, Pool remember theirs too (`remember_allocators`) (example 08).
- Syntax trap met twice while writing these examples: `if p (cast(*string) p).* = x;` parses the parentheses as part
  of the condition ("Expected a statement before this semicolon"). Write `if p { (cast(*string) p).* = x; }`.

| Allocator | Use | Verified notes |
|---|---|---|
| default heap | general | x64: stripped-down rpmalloc 1.4.4 without thread caches; arm64 macOS: wrapper over C malloc (read the CAPS name). Thread-safe |
| `temp` | scratch until a reset | section below |
| `Flat_Pool` + `flat_pool_allocator_proc` | arena for one lifetime | reserves 256 MiB of address space on first use; `get`, `reset(*p, overwrite_memory=false)`, `fini`; no setup; 8-byte `alignment` field |
| `Pool` + `pool_allocator_proc` | older arena | 64 KiB blocks; call `set_allocators(*pool)` **before** pushing it; `reset` keeps blocks, `release` frees them |
| `rpmalloc` module | threaded heap, real heaps | `rpmalloc_allocator_proc(.STARTUP, 0, 0, null, null)` once; `create_heap`/`destroy_heap` per level/request (example 13) |
| `Bucket_Array(T, N)` | stable addresses | `bucket_array_add -> (locator, pointer)`, `bucket_array_remove`, `for` with `remove` |
| `Overwriting_Allocator`, `Unmapping_Allocator` | debugging | below |

- Your own allocator: example 09 is a complete tested fixed-buffer arena (align the **address**, null when full,
  RESIZE extends the last block in place, FREE ignored, IS_THIS_YOURS and CAPS answered). In any bump allocator a
  growing `[..]` abandons its old buffers (500 strings: 20 KiB instead of 4 KiB in example 12): `array_reserve` first.
- Choose by lifetime: scratch for a frame/function → `temp`; things that die together (level, request, file) → an
  arena / Flat_Pool / rpmalloc heap pushed around the code, freed in one call; long-lived and owned by one system →
  its own heap, or the default heap with `defer free`; individually freed with unclear ownership → default heap,
  and treat it as a design smell (how_to/200). Library code that never frees works unchanged under a pushed arena.
- deep dive: reference/allocators.md

## Finding memory bugs

- `#import "Basic"()(MEMORY_DEBUGGER=true);` once in the program (program parameters apply everywhere; a second
  import with parameters is an error). `report_memory_leaks()` prints, to stdout, groups like `----- 480 bytes in 3
  allocations -----` with the allocating call stack, then `Total: ...` and `Marked as non-leaks: ...`.
  `this_allocation_is_not_a_leak(p)` for intentional globals (an empty macro when the debugger is off). Temp, Pool
  and Flat_Pool allocations are not tracked. Needs stack traces (not with `-o`) (example 14).
- Double free: a report with three stacks (this free, earlier free, allocation); freeing a pointer Basic never
  allocated: "not generated by Basic.alloc" and exit 1. `MEMORY_DEBUGGER_REPORT_ASSERTS=true` (since 0.2.031)
  asserts after each report, so you stop at the first problem (example 15).
- `get_overwriting_allocator(base)`: 0xcd in fresh (uninitialized) and freed memory, asserts on double/foreign free.
  The base heap may recycle freed blocks (macOS malloc zeroes them): use it over a pool for clean results (example 16).
  `get_unmapping_allocator()`: own pages per allocation, guard page after it, freed pages inaccessible: overruns and
  use-after-free crash at the access, but the crash text is misleading (Linux "SEGV_ACCERR ... write to read-only
  memory" even for reads, macOS "SIGBUS ... invalid address alignment") (example 17). `get_capabilities` calls with
  null data, which both wrappers assert on: call `a.proc(.CAPS, 0, 0, *name, a.data)`.
- deep dive: reference/allocators.md#debugging-allocators

## Temporary storage

- A per-thread bump allocator at `context.temporary_storage`. `temp` (= `temporary_allocator`) is its Allocator;
  `tprint`, `talloc(n)`, `temp_c_string`, `New(T,, temp)`, `arr.allocator = temp`, `push_allocator(temp)`. `free` is
  a no-op. Return temp memory freely; it lives until the next reset (example 18).
- Release: `reset_temporary_storage()` at a point where nothing temporary is alive (end of frame/request/file), or
  scoped: `auto_release_temp();` (macro, rolls back at scope exit) or `mark := get_temporary_storage_mark(); defer
  set_temporary_storage_mark(mark);` (example 19). Frame loop: allocate freely, `copy_string` what must survive, reset
  once per iteration (example 20).
- Size: the main thread's first page is `Build_Options.temporary_storage_size` (32768 bytes, a static buffer; set it in
  a build.jai, example 21); threads `thread_init(..., temporary_storage_size = 16384)`. When a request does not fit,
  Basic adds an **overflow page** of max(request, page size) from `overflow_allocator` (default heap) and abandons the
  rest of the page; a reset frees all overflow pages again. Nothing fails, frames just start calling malloc: size the
  storage from `high_water_mark` (zeroed by the reset, so read it before).
- Allocations are 8-byte aligned. RESIZE copies unless the new size fits the old padded size.
- Bugs: a `tprint` result stored past a reset still looks valid until reused. Debug builds:
  `#import "Basic"()(TEMP_ALLOCATOR_OVERWRITE_MEMORY=true)` stamps reset memory with 0xdb (renamed from
  `TEMP_ALLOCATOR_POISON_FREED_MEMORY` in 0.2.028; example 22). Never hand temp memory to a thread that outlives your
  reset. Library results in temp: `get_completed_work`, `get_stack_trace_strings`, `get_path_of_running_executable`,
  `System.get_error_value_and_string` (description).
- deep dive: reference/temporary-storage.md

## Build modes and what they cost

| Command | Effect (Default_Metaprogram + set_optimization) |
|---|---|
| `jai f.jai` | debug: LLVM -O0, array bounds/cast/null checks ON, stack traces ON, debug info |
| `jai f.jai -od` | OPTIMIZED: LLVM O2, checks OFF, **stack traces kept** |
| `jai f.jai -o` | VERY_OPTIMIZED: O3 + loop/SLP vectorizers, checks OFF, stack traces OFF |
| `jai f.jai -very_debug` | VERY_DEBUG: same checks as debug in 0.2.032 (overflow checks still off) |
| `jai f.jai -x64` | fast non-LLVM backend: x86-64 targets only (on an arm64 Mac: "The x64 backend supports only x64 CPUs") |
| `-no_inline` (0.2.003), `-no_backtrace_on_crash`, `-output_ir` (.ll files in .build/), `-natvis` | bytecode inliner off; no crash handler; LLVM IR; Windows-style type names |
| old `-release` / `-release_debug` | still work but print "*** Warning: -release will go away ... Please use -o or -optimized instead." (since 0.2.026, even with -quiet); `-debug` is now "Unknown argument" (it became `-debugger` in 0.1.020); `-optimzed` (the typo in `-help`) is rejected |

- Read the active settings inside the program: `BUILD :: #run get_build_options();` (example 28). Finer control in a
  build.jai: `set_optimization(*o, .OPTIMIZED)`, then fields `array_bounds_check` (OFF/ON/ALWAYS),
  `cast_bounds_check` (OFF/NONFATAL/FATAL), `null_pointer_check`, `arithmetic_overflow_check` (default **OFF**
  everywhere; .FATAL to enable, example 29), `stack_trace`, `backend`, `llvm_options`, `temporary_storage_size`.
- Measured (median ms of 9 runs; dot 4M f64 / sieve 10M / matmul 256³ / fib(30); full tables and commands in
  reference/performance.md):

| Build | Mac M2 Max | powerslabs 285K | compile (wall) Mac / Linux |
|---|---|---|---|
| debug | 17.8 / 112.7 / 108.0 / 11.6 | 9.6 / 65.4 / 44.7 / 7.2 | 0.19 / 0.17 s |
| debug, checks off | 15.3 / 91.9 / 84.1 / 11.4 | 8.8 / 50.0 / 37.5 / 6.9 | |
| debug, no stack traces | 18.2 / 113.6 / 108.8 / **5.6** | 10.3 / 73.6 / 45.7 / **2.7** | |
| -od | 3.9 / 16.9 / 12.6 / 7.5 | 3.5 / 18.0 / 10.1 / 5.1 | 0.68 / 0.73 s |
| -o | 3.8 / 13.1 / 12.7 / **3.2** | 3.4 / 18.3 / 10.1 / **2.2** | 0.60 / 0.72 s |
| -o + bounds checks | 3.8 / 17.1 / 14.2 / 3.0 | 4.7 / 18.0 / 10.4 / 2.2 | |
| -x64 (Linux only) | | 9.1 / 59.9 / 45.5 / 14.6 | — / 0.13 s (backend 2 ms vs LLVM 110–210 ms) |

- Takeaways: -o is 2–9× faster than debug on loops (Mac 5–9×, the Intel machines 2–4.5×), 3–4× on calls.
  Stack-trace nodes cost **2–2.7× on call-heavy code** (fib) and nothing on loops: `-od` keeps them, so profile
  call-heavy code with that in mind. The debug checks add 9–31% on loops; bounds checks alone add 0–38% under -o.
  The x64 backend runs its code generation 50–100× faster than LLVM -O0 but makes code like LLVM -O0
  on loops and 2× slower on calls; `set_optimization` on x64 only removes checks. **`x64_options.
  enable_register_allocation = true` crashed even a hello world (exit 139) in 0.2.032.**
- Local control: `#no_abc` / `#no_aoc` (no array bounds / arithmetic overflow checks) after a procedure's signature,
  before a block (`#no_aoc { x += 1; }`) or on a for loop (`for i: 0..n-1 #no_abc { }`); `cast,no_check(u8) x` and
  `cast,trunc(u8) x` skip the cast check (examples 29, 37). `inline`/`no_inline` on a declaration
  (`f :: inline (x: int) -> int {...}`) or a call (`inline f(x)`, `no_inline f(x)`) (example 34).
- Layout: declaration order, natural alignment: order large-to-small (`{u8,u64,u8}` = 24 bytes, reordered 16).
  `#align 64` on a member or local variable (false sharing). **`#no_padding` only drops trailing padding**: members
  keep offsets 0/8/16, size becomes 17, and array elements after the first are misaligned (example 30). Use it only for
  structs that are already packed. SOA: write it by hand or see jai-metaprogramming (modules/Soa.jai is experimental).
- `#asm` is **x86-64 only**; on arm64 an `#asm` block fails ("The target of this workspace does not support x64
  asm", example 32). Guard with `#if CPU == .X64` and add a fallback (example 31). **Silent pitfall on every platform:
  an asm operand whose address is taken anywhere in the procedure (passing it to `print` does that) gets only "Info:
  This variable cannot be used as a register operand, because its address gets taken..." and the instruction has no
  effect** (x64 debug, -o and -x64 alike); on arm64 that Info even replaces the error, so the block compiles to
  nothing. Copy the result into another variable before printing (example 33). Machine_X64 (x64 only):
  `get_cpu_info()`, `check_feature(info.feature_leaves, .AVX2)`, `prefetch`, `rdtsc`, `pause`, fences; `#asm AVX2 {}`
  for per-block features. `modules/SIMD.jai` is a scalar **prototype** of a SIMD API (`SIMD_Array(N, T)` with
  operators, `horizontal_sum`): no speedup. Real SIMD: x64 `#asm`, or LLVM's vectorizers under `-o`.
- Bit_Operations: `popcount`, `bit_scan_forward/reverse` (1-based, 0 for 0), `byte_swap`: x64 asm, loops elsewhere.
  Measured with -o (64 MiB, 1M u32; Mac / powerslabs): `Hash.fnv1a_hash` 0.8 / 1.4 GB/s; `xxHash.native_XXH64` 13.8 /
  12.5 GB/s; `native_XXH32` 4.7 / 7.7 GB/s; `meow_hash` 26.5 GB/s (x64 only); `Sort.quick_sort` 103 / 82 ms;
  `IntroSort.intro_sort` 84 / 70 ms; `RadixSort` ranks 9.1 / 8.7 ms.
- Timing: `t0 := current_time_monotonic(); ...; ns := to_nanoseconds(current_time_monotonic() - t0);`
  (`Apollo_Time`; also `to_float64_seconds`, `to_microseconds`). `seconds_since_init()` (the replacement for the
  removed `get_time()`) counts from its own **first call**; wall-clock time is `to_calendar(current_time_consensus())`
  (replaces `get_system_time()`/`System_Time`, removed 0.2.002). **`System.read_cpu_counter()` (0.2.019) is rdtsc on
  x64 but only the nanosecond field of clock_gettime on arm64 Unix: it wraps every second.** Benchmark: warm-up,
  ≥7 runs, median, keep results live, same flags (example 34).
- deep dive: reference/performance.md

## Profiling

- **Iprof** plugin, no code changes: `jai main.jai +Iprof` (procedures with ≥ 30 expressions), `-min_size 1`
  (almost all), `-modules`, `-csv out.csv` (written at run time). When `main` returns it logs a table
  `All Threads  self (ms)  hier (ms)  calls`, then per thread (since 0.2.031). Skips `#c_call`/`#no_context`,
  polymorphic procs, macros and procs tagged `@NoProfile` (example 40). Uses `read_cpu_counter`, so on a Mac a zone
  can come out wrong or negative: trust Linux/x64 numbers more.
- **Performance_Report** plugin (`jai f.jai +Performance_Report`): compile-time costs (#run time, polymorph counts per
  procedure, bytecode inlining) — for slow builds, not slow programs.
- Sampling profilers work on Jai executables (symbols are `name_<hex>` in debug builds, line numbers via dSYM/DWARF):
  macOS `sample <pid> 1 -file out.txt`, `xcrun xctrace record --template 'Time Profiler' --launch -- ./prog`; Linux
  `valgrind --tool=callgrind ./prog` + `callgrind_annotate` (per-line counts on the .jai source, no root needed).
  `perf` needs `kernel.perf_event_paranoid` ≤ 2 (it was 3/4 on our machines without root).
- No Tracy binding ships with the compiler. A community one exists (rluba/jai-tracy, MIT; not built here); the C route
  (build `TracyClient.cpp`, declare the `___tracy_*` functions of `TracyC.h` with `#foreign`) is also untested here
  (see c-perf for the Tracy side). `telemetry3` binds RAD Telemetry (commercial; only Windows DLLs ship).
- deep dive: reference/profiling.md

## Threads

- `modules/Thread`: `thread_init(*t, proc, temporary_storage_size = 16384, name = "") -> bool` (proc is
  `(*Thread) -> s64`; `t.data` is yours), `thread_start(*t)` (threads are created suspended), `thread_is_done(*t, ms)`
  (0 = poll, -1 = wait), `thread_deinit(*t)` (joins, frees its temp storage). Threads get `thread_index` 1, 2, ...
  (main = 0; never reused) and their own temporary storage (example 23). **`thread_deinit` of a thread that was
  initialized but never started hangs forever** (Mac and Linux), and so does `shutdown` of a never-started
  Thread_Group: always start what you init.
- `Mutex` (`init/lock/unlock/destroy`; recursive on POSIX), `Semaphore` (`init(*s, n)`, `signal`, `wait_for(*s, ms =
  -1) -> .SUCCESS/.TIMEOUT/.ERROR`), `Condition_Variable` (`wait(*cv, *mutex)`, `wake`, `wake_all`) (example 27).
- `Thread_Group`: `init(*g, n, proc, enable_work_stealing = false)`, **`g.logging = false`** (default true: logs every
  work item), `start`, `add_work(*g, *item)`, `get_completed_work(*g)` (array in temp storage), `shutdown(*g)`. Proc:
  `(group, thread, work: *void) -> Thread_Continue_Status`. Work items are your memory (example 25).
- Atomics: intrinsics `compare_and_swap(*x, old, new) -> (ok, old_value)`, `atomic_exchange`, `atomic_load`,
  `atomic_store` (≤ 8 bytes; since 0.2.030, AcqRel on ARM64); `#import "Atomics"` for `atomic_add` (returns the old
  value), `atomic_increment`, `atomic_decrement` (true at zero), `atomic_and/or/xor` (example 26).
- Safety rules: temp storage is per thread (never share it); the default heap and rpmalloc are thread-safe; `temp`,
  Pool, Flat_Pool and arenas are not (check `get_capabilities(a)` for `MULTIPLE_THREADS`). `DO_RACE_DETECTOR=true`
  fails: the Race_Detector module is not shipped. Also: `Shared_Memory_Channel` (IPC), `File_Watcher`.
- deep dive: reference/threads.md

## Debugging

- Runtime failures go to **stderr**, then the crash handler prints native frames and the program exits 1:

| Failure (debug build) | Message starts with |
|---|---|
| index out of range | `Array bounds check failed. (The attempted index is 3, but the highest valid index is 2). Site is file:line.` + `Panic.` |
| narrowing cast | `Cast bounds check failed.  Number must be in [0, 255]; it was 302.` |
| *T passed as T param | `Null pointer check failed: Argument 1 is undergoing an automatic dereference, but the pointer is null.` |
| p.field via null | Linux `SEGV_MAPERR ... Null Pointer Exception`; macOS `SEGV_ACCERR ... write to read-only memory` (wrong wording) |
| overflow (if enabled) | `Arithmetic overflow. We tried to compute:` + operands + operand type |
| `assert(c, fmt, ..)` | `file:line,col: Assertion failed: msg` + `Stack trace:` with Jai frames |
| integer ÷ 0 | Linux `SIGFPE ... integer division by zero`; **macOS arm64: no trap, result 0** |
| stack overflow | nothing printed; exit 139 (Linux) / 132 (macOS) |
| `debug_break()` with no debugger | `Breakpoint hit. Stack trace:` |

- `assert` calls `context.assertion_failed(loc, message) -> bool` (true = break; handlers must return bool since
  0.1.077); install your own to collect failures (example 35). **`-o` keeps asserts** (empty "Stack trace:"); only
  `#import "Basic"()(ENABLE_ASSERT=false)` removes them, condition included. Under `-o`/`-od` the bounds, cast and
  null checks are gone: an out-of-range read silently returns garbage.
- Stack trace nodes (`context.stack_trace`, on unless -o): `print_stack_trace`, `get_stack_trace_strings` (since
  0.2.020; replaces `get_stack_trace_string`), `pack_stack_trace(context.stack_trace)`; `node.line_number` is the call
  line (example 39). `-o` builds print only native frames.
- Debuggers: default builds carry debug info (macOS writes `prog.dSYM`). lldb: `b file.jai:42`, `b total_mass` (the
  symbol is `total_mass_<hex>`; `main` is `__program_main`), `frame variable`, `p s` → `(count = 2, data = "p0")`,
  `parray 3 view.data`, `finish` shows the return value. gdb: `break file.jai:42`, `print *s.data@s.count`,
  `print *view.data@view.count` (gdb reads `string.data` as a C string, past `count`). Only natvis for Visual Studio
  ships (`editor_support/msvc/jai.natvis`, use with `-natvis`); no lldb/gdb formatters are needed for basic types.
- `#import "Debug"(USE_GRAPHICS=false)`: `backtrace()` (native frames as strings), `is_debugger_present()`,
  `breakpoint()` (breaks only under a debugger). **`Debug.init()` changes assert semantics**: it installs
  `break_assert`, which prints and **continues** without a debugger (with USE_GRAPHICS=true on macOS: prints and exits
  3). `Debug.no_assert/print_assert/trace_assert` don't compile as handlers (they return nothing; handlers return bool).
- Compile-time crashes in `#run` print a user-level stack trace and suggest `-debugger` (interactive bytecode
  debugger); `#dump` after a procedure's signature prints its bytecode at compile time. Native frames → source lines:
  Linux `addr2line -f -e prog 0xADDR` (non-PIE); macOS `lldb --batch -o "image lookup -a <symbol address + offset>"`.
- deep dive: reference/debugging.md (real lldb and gdb sessions)

## Recipes (each one is a passing example)

```jai
// Arena around code that allocates and never frees (example 12)
pool: Flat_Pool;
{
    push_allocator(flat_pool_allocator_proc, *pool);
    names = make_names(500);                  // every allocation inside comes from the pool
}
reset(*pool);                                 // ...and is gone in one call

// Frame loop with temporary storage (example 20)
for frame: 1..3 {
    labels := score_labels(frame);            // tprint / temp arrays inside
    array_add(*kept, copy_string(tprint("frame % best: %", frame, labels[2])));   // copy out what must survive
    reset_temporary_storage();
}

// A C callback that gets its context back through the user pointer (example 05)
on_event :: (value: s32, user: *void) -> s32 #c_call {
    saved := cast(*#Context) user;
    push_context saved.* { print("event %\n", value); }
    return value * 2;
}

// #add_context fields into every new thread (example 24)
thread_init_handler = (t: *Thread) { t.starting_context.request_limit = context.request_limit; };
```

## Pitfalls checklist (all observed in 0.2.032)

- `context.x = v` is not scoped; `push_context .{only_add_context_fields}` may not compile (use copy-edit-push).
- `push_context {}` and threads start from a default context: no #add_context values (threads), no temporary storage
  (`push_context {}`: tprint leaks to the heap).
- `free(s)` and `free(p)` use `context.allocator`, not the allocator that made the memory; `[..]` arrays remember
  theirs, strings and views don't.
- Old code: allocator arguments, `Context`, `__temporary_allocator`, `initialized =`, `get_time` (table below).
- Temp memory: 8-byte aligned, dies at the next reset (stamp it with TEMP_ALLOCATOR_OVERWRITE_MEMORY in debug).
- Integer overflow wraps silently unless `arithmetic_overflow_check` is set; integer division by zero returns 0 on
  arm64 macOS; stack overflow prints nothing.
- `#no_padding` doesn't pack; `#asm` doesn't exist on arm64, and an asm operand whose address is taken is silently
  ignored everywhere (only an Info line); `SIMD.jai` is scalar; `read_cpu_counter` wraps every second on arm64;
  `seconds_since_init()` starts at its first call.
- `Thread_Group.logging` is on by default; `thread_init_handler` is global (one hook for the program);
  `thread_deinit`/`shutdown` without a prior start hang; `DO_RACE_DETECTOR` needs a module that is not shipped;
  `enable_register_allocation` (x64 backend) crashes; `#exists(context.field)` is unreliable for #add_context fields.
- A build.jai workspace ignores `-quiet` (set `text_output_flags = 0`) and must call
  `set_build_options_dc(.{do_output = false})` (jai-metaprogramming).

## Experiments to teach with (change one thing, predict, run)

- Example 02: replace a `push_context` with `context.level = 50;` and watch the value leak out of the block.
- Example 24: delete the `thread_init_handler` assignment: the second thread loses the #add_context values.
- Example 34 or `bench.jai` (reference/performance.md): build with nothing, `-od`, `-o`; compare the stderr timings.
- Example 33: move the `print` of `x` into a new variable and the dropped `add` starts working.
- Example 11: add another `old_*.jai` file with code from an old tutorial and read what 0.2.032 says.
- Example 36 with `-o`: the bounds check disappears and the read returns garbage instead of panicking.
- Add `#import "Basic"()(MEMORY_DEBUGGER=true);` and `report_memory_leaks()` to any example that allocates.
- Example 22 without `TEMP_ALLOCATOR_OVERWRITE_MEMORY`: the stale temp string still prints, which is the bug.
- Example 40 without `-min_size 1`: Iprof instruments only procedures with at least 30 expressions.

## Reading older code (all verified on 0.2.032; example 11 compiles every left-hand form)

| Old form (tutorials, blogs, pre-2026 repos) | Current form | Changed | 0.2.032 says |
|---|---|---|---|
| `c: Context;`, `-> Context` | `#Context`; `Context_Base` for allocator/logger parameters | `#Context` 0.1.096, `Context` removed 0.2.002 | "Undeclared identifier 'Context'." |
| `alloc(n, a)`, `copy_string(s, a)`, `New(T, allocator = a)`, `free(p, a)` | `alloc(n,, a)`, `copy_string(s,, a)`, `New(T,, a)`, `free(p,, a)` | 0.1.080 | "Too many arguments: Wanted 1, got 2." / "Argument name 'allocator' ... not found" / "did not match any of the possible overloads" |
| `__temporary_allocator` | `temp` (= `temporary_allocator`) | 0.0.096, removed 0.2.029 | "Undeclared identifier '__temporary_allocator'." |
| `New(T, initialized = false)`, `NewArray(n, T, initialized = false)` | `initialize = false` | 0.2.032 | "Argument name 'initialized' (number 2) is not found ..." |
| `get_time()` | `seconds_since_init()` or `current_time_monotonic()` differences | removed 0.2.002 | "Undeclared identifier 'get_time'." |
| `get_system_time()`, `System_Time` | `to_calendar(current_time_consensus())` → `Calendar_Time` | removed 0.2.002 | undeclared identifier |
| `get_stack_trace_string(node)` | `get_stack_trace_strings(node)` (temp array, one line each) | 0.2.020 | undeclared identifier |
| `Push_Temporary()` | `auto_release_temp()` or temp marks | removed 0.1.028 | undeclared identifier |
| `thread_create` / `thread_destroy` / `thread_uninit` | your own `Thread` + `thread_init` / `thread_deinit` | removed 0.1.071 | undeclared identifier |
| `lock_cmpxchg(...)` | `ok, old := compare_and_swap(*x, old, new)` (intrinsic since 0.2.003) | removed 0.2.009 | undeclared identifier |
| `TEMP_ALLOCATOR_POISON_FREED_MEMORY` | `TEMP_ALLOCATOR_OVERWRITE_MEMORY` | 0.2.028 | "... is not found in the program parameters." |
| allocator as a bare procedure | `Allocator.{proc, data}`, `Allocator_Proc`, `push_allocator(proc, data)` | 0.0.096 | "Type mismatch. Type wanted: Allocator; ..." |
| `rdtsc()` / `QueryPerformanceCounter` for timing | `current_time_monotonic()`; `read_cpu_counter()` only for x64 tick counts | `read_cpu_counter` 0.2.019 | — |
| `jai -release f.jai`, `-release_debug` | `-o`, `-od` | warning since 0.2.026 | "*** Warning: -release will go away ..." |
| `jai -debug f.jai` (interactive debugger) | `-debugger` | 0.1.020 | "Unknown argument '-debug'." |
