---
name: odin-performance
description: High-performance Odin and expert memory management — the Allocator interface (mem.Allocator, Allocator_Mode, writing your own allocator proc), context.allocator/temp_allocator and free_all/DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD, every strategy from gingerbill's memory-allocation series (arena/linear, stack, pool, free list, buddy) mapped to the real core implementations (mem.Arena, mem/virtual.Arena growing/static/buffer, mem.Stack, Small_Stack, Scratch, Dynamic_Arena, Rollback_Stack, Buddy_Allocator, mem/tlsf, container/pool, handle_map), leak and double-free detection with Tracking_Allocator, nil/panic allocators, virtual memory reserve/commit, frame/request/per-thread arenas, slab/size-class allocators, handles instead of pointers, data-oriented design with #soa, SIMD (core:simd, #simd, enable_target_feature), intrinsics, hidden allocations, bounds-check and inlining control, profiling (spall instrumentation, perf, Instruments, Tracy) and benchmarking. Load before optimizing Odin code or designing its memory strategy; basics in the odin skill.
---

# Odin performance and memory

Validated with Odin **dev-2026-11a** on macOS arm64 (M2 Max), Linux x86_64 (Core Ultra 9 285K) and Jetson AGX Orin
(aarch64): every allocator below was compiled and run (`-vet -strict-style`, `-o:speed`). Names and signatures move
between monthly releases: before writing code, check the exact proc in `$(odin root)/core/mem/allocators.odin`,
`core/mem/virtual/arena.odin`, `base/runtime/core.odin` (or `library_search` the pinned core sources). Verify; don't
trust these. The odin skill covers the toolchain; odin-targets covers freestanding/WASM memory.

## The allocator interface

```odin
Allocator      :: struct { procedure: Allocator_Proc, data: rawptr }
Allocator_Proc :: #type proc(allocator_data: rawptr, mode: Allocator_Mode, size, alignment: int,
                             old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, Allocator_Error)
Allocator_Mode :: enum byte { Alloc, Free, Free_All, Resize, Query_Features, Query_Info, Alloc_Non_Zeroed, Resize_Non_Zeroed }
Allocator_Error :: enum byte { None, Out_Of_Memory, Invalid_Pointer, Invalid_Argument, Mode_Not_Implemented }
```
- Every allocating proc in core takes `allocator := context.allocator` (or `context.temp_allocator`): `make`, `new`,
  `append` (uses the array's own allocator), `strings.clone`, `fmt.aprintf`, `os.read_entire_file(path, allocator)`.
  Free with the same allocator: `delete(x, a)`, `free(p, a)`, `free_all(a)`. `mem.free_with_size` /
  `mem.free_bytes` pass the size for allocators that need it (size classes, buddy).
- Write your own by switching on `mode`; answer `.Query_Features` with the `Allocator_Mode_Set` you support (callers
  such as Tracking_Allocator use it to decide e.g. clear-on-free_all) and return `.Mode_Not_Implemented` otherwise;
  implement `.Resize` with `mem.default_resize_bytes_align(old, size, alignment, self, loc)` if you have nothing better.
  Validated: a counting wrapper (forwards to `backing.procedure`) and a size-class slab (below).
- `context.allocator` defaults to the heap (`runtime.heap_allocator`, malloc-based; on WASM the wasm page allocator),
  `context.temp_allocator` to a growing arena (`runtime.Default_Temp_Allocator`, 4 MiB blocks,
  `-define:DEFAULT_TEMP_ALLOCATOR_BACKING_SIZE=…`) which is **`@thread_local`**: each thread has its own; free it in
  threads you create with `runtime.default_temp_allocator_destroy(&runtime.global_default_temp_allocator_data)`
  (runtime docs say so for `thread.create`/`run` with `init_context`).
- Override per scope: `context.allocator = mem.arena_allocator(&a)` — everything called below (including core
  procs) now allocates from the arena. Context is restored at scope exit.

## Temp allocator discipline

- One `free_all(context.temp_allocator)` per frame / request / loop iteration. Anything from `fmt.tprintf`,
  `fmt.ctprintf`, `strings.*(…, context.temp_allocator)` dies then: never store it.
- Nested scratch inside a long-lived frame: `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()` at the top of a block
  (begin/end temp via `@(deferred_out)`; rolls the default temp arena back at block exit). It only acts when
  `context.temp_allocator` is the default one; for your own virtual arenas use `vmem.arena_temp_begin/arena_temp_end`,
  for `mem.Arena` `mem.begin_arena_temp_memory/end_arena_temp_memory`.
- `-default-to-nil-allocator` and **every freestanding target** (forced by the compiler, incl. `freestanding_wasm32`):
  `context.allocator` and `temp_allocator` are nil allocators — `make` returns `.Out_Of_Memory`. Supply an arena or
  `runtime.default_wasm_allocator()` yourself (odin-targets).

## Strategies → core implementations (gingerbill.org "Memory Allocation Strategies" 001–006)

| Strategy (article) | Core type and init | Free one? | Notes (validated) |
|---|---|---|---|
| Linear / arena (002) over a buffer | `mem.Arena` + `mem.arena_init(&a, buf[:])`, `mem.arena_allocator(&a)` | no | `free_all`; temp marks `mem.begin_arena_temp_memory`; tracks `peak_used` |
| Arena on virtual memory | `vmem.Arena` (`import vmem "core:mem/virtual"`): `arena_init_growing(&a)` (chained blocks, 1 MiB min, 8 MiB commit), `arena_init_static(&a, reserved = 1*mem.Gigabyte)` (one reservation, commits on demand; default reserve 1 GiB on 64-bit), `arena_init_buffer(&a, buf[:])` | no | `vmem.arena_allocator`, `vmem.arena_free_all`, `vmem.arena_destroy`, `vmem.new/make(&a, …)` return `(v, err)`; buffer kind returns `.Out_Of_Memory` when full; **default choice for arenas** |
| Stack (003) | `mem.Stack` + `mem.stack_init(&s, buf[:])` | LIFO only | header per allocation; out-of-order free is an error |
| Small stack | `mem.Small_Stack` + `mem.small_stack_init` | LIFO | smaller headers, no strict ordering checks |
| Stack with rollback, growing | `mem.Rollback_Stack` + `mem.rollback_stack_init(&s)` (dynamic, 4 MiB blocks) or `(&s, buf[:])` | LIFO/last | used by the test runner per thread |
| Scratch / ring | `mem.Scratch` + `mem.scratch_init(&s, size)` | last only | wraps around: old allocations silently invalidated; oversize → backup allocator + warning |
| Pool (004), fixed-size objects | `core:container/pool`: `pool.Pool(T)`, `pool.init(&p, "link")` (T has an intrusive `link: ^T`), `pool.get/put` | yes | stable pointers, thread-safe, backed by a virtual growing arena; validated reuse of freed element |
| Block pool / "dynamic pool" | `mem.Dynamic_Arena` + `mem.dynamic_arena_init(&a)` (64 KiB blocks, out-of-band > 6554 B) | no (reset/free_all) | what older docs call `Dynamic_Pool` |
| Free list (005), general purpose | `core:mem/tlsf`: `tlsf.init(&t, backing, initial_pool_size)` or `tlsf.init(&t, buf[:])`, `tlsf.allocator(&t)`, `tlsf.destroy` | yes, O(1) | Two-Level Segregated Fit; good real-time general allocator |
| Buddy (006) | `mem.Buddy_Allocator` + `mem.buddy_allocator_init(&b, buf, alignment)` (power-of-two buffer, aligned) | yes | **dev-2026-11a limitation**: after small alloc/free pairs the halves don't merge back into the root block (64 KiB buffer: alloc 100 + 3000, free both → 60000-byte alloc = `.Out_Of_Memory`; `free_all` restores). Size for ≤ half the buffer or use tlsf |
| Thread-safe wrapper | `mem.Mutex_Allocator` + `mem.mutex_allocator_init(&m, backing)` | — | one lock around any allocator |
| No-size-info adapter | `mem.Compat_Allocator` | — | stores sizes so allocators needing `old_size` work with code that doesn't pass it |
| Nothing / trap | `mem.nil_allocator()` (returns nil, no error), `mem.panic_allocator()`; program-wide `-default-to-nil-allocator`, `-default-to-panic-allocator` | — | catch hidden allocations in hot paths or freestanding code |

- Handles instead of pointers: `core:container/handle_map` — `hm.Dynamic_Handle_Map(Entity, hm.Handle32)` (T needs a
  `handle` field; generational `idx`/`gen`), `hm.add/get/remove/is_valid`, static variant for fixed capacity; stale
  handles are detected (validated). Also `core:container/xar` (exponential array: stable addresses while growing).
- Choosing: lifetime-grouped data → arena (per frame, per request, per level, per job); same-size objects with
  individual lifetimes → pool / handle map; truly general → heap or tlsf; scoped scratch → temp allocator + guard.

## Leak and misuse detection (Tracking_Allocator)

```odin
track: mem.Tracking_Allocator
mem.tracking_allocator_init(&track, context.allocator)
track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array // default: panic on bad free
context.allocator = mem.tracking_allocator(&track)
defer {
	for _, e in track.allocation_map { fmt.eprintfln("LEAK %v bytes @ %v", e.size, e.location) }
	for e in track.bad_free_array   { fmt.eprintfln("BAD FREE %p @ %v", e.memory, e.location) }
	mem.tracking_allocator_destroy(&track)
}
```
- Wrap it `when ODIN_DEBUG { … }` in `main`. Output (validated): `LEAK 24 bytes @ …/main.odin(233:12)`,
  `BAD FREE 0x16B396448 @ …(236:2)`. Also `total_memory_allocated`, `peak_memory_allocated`, `total_allocation_count`,
  `current_memory_allocated`; `tracking_allocator_reset/clear`. Thread-safe (has a mutex).
- `odin test` wraps every test in one automatically; add `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true` so leaks fail CI.
- Complement with `-sanitize:address` (use-after-free, overflow; see odin skill for platform caveats) and `-debug`.

## Virtual memory

- `vmem.reserve(size)`, `vmem.commit(ptr, size)`, `vmem.decommit`, `vmem.release`, `vmem.protect(ptr, size, {.Read, .Write})`
  (`Protect_Flags`), `vmem.reserve_and_commit`. Reserve huge (GiBs) address ranges up front, commit as you grow:
  pointers stay stable, no copying (what `arena_init_static` does). Guard pages via `protect(…, {})`.
- Memory-mapped files: `vmem.map_file(path_or_file, flags) -> (data, err)` / `vmem.unmap_file(data)`
  (`core/mem/virtual/file.odin`).
- Bootstrap a struct that owns its arena: `vmem.arena_growing_bootstrap_new(T, "arena_field")`.

## Patterns beyond the series (validated in tests/patterns)

- **Double-buffered frame arenas**: two `vmem.Arena`s; each frame flip and `arena_free_all` the one used two frames
  ago, so data from the previous frame (last frame's UI, render lists) stays valid one more frame.
- **Per-request/per-job arena**: create a growing arena per request/thread, set `context.allocator`, `arena_destroy`
  once at the end — no frees, no leaks, no locks. Per-thread arenas with 8 threads × 100k appends: ~1.7 ms (M2 Max).
- **Size-class slab**: power-of-two classes (16…512 B), a free list per class threaded through the freed blocks,
  blocks carved from a virtual arena, `Free_All` resets everything. Needs the size on free (`mem.free_with_size`,
  `delete` of slices passes it); `free(ptr)` alone can't find the class.
- Lock-free-ish allocation across threads = don't share: per-thread arenas or per-thread pools, hand results back
  by value/handle; `mem.Mutex_Allocator` only for rarely-hit shared allocators.

## Avoiding hidden allocations

- Allocate: `fmt.aprint*` (heap), `fmt.tprint*` (temp), `strings.clone/concatenate/split/join`, `append` growth,
  map insertion/growth, `make`, `os.read_entire_file`, `json.marshal/unmarshal`, `strings.to_lower`…
  Don't: `fmt.println/printf` (stack buffer), `fmt.bprintf(buf[:], …)` (your buffer), `fmt.sbprintf(&builder, …)`
  (builder's allocator), slicing, `for in`.
- Pre-size: `make([dynamic]T, 0, n)`, `reserve(&d, n)`, `make(map[K]V, n)`; `core:container/small_array` for
  bounded inline storage; fixed arrays `[N]T` on the stack.
- Prove it: run the hot path with `context.allocator = mem.panic_allocator()` (and temp) or a counting allocator, or
  build with `-default-to-panic-allocator`.
- `-dynamic-map-calls` trades map speed for code size.

## Data-oriented layout

- `#soa[N]T`, `#soa[]T`, `#soa[dynamic]T`: struct-of-arrays with array-of-structs syntax (`ps[i].x`, `for &p in ps`);
  `ps.x` is the column pointer (validated: `&ps.x[0] == &ps[0].x`). Iterate one hot field for cache/SIMD wins.
- Hot/cold splitting, indices (`u32`) instead of pointers, `bit_set` flags instead of bools, `#packed`/`bit_field`
  for wire formats, `#align(64)` on per-thread structs to avoid false sharing; `@(align=N)` works on variables since
  dev-2026-11.
- Process in batches; sort by key before processing; keep arrays contiguous (`[dynamic]T`, not linked lists).

## SIMD and intrinsics

```odin
acc: #simd[8]f32                                         // or simd.f32x8; arithmetic operators work lane-wise
v := intrinsics.unaligned_load((^#simd[8]f32)(&xs[i]))   // load from a slice
acc += v; s := simd.reduce_add_bisect(acc)
@(enable_target_feature = "avx2,fma")                    // per-proc ISA; dispatch at runtime yourself (core:sys/info)
saxpy :: proc(a: f32, x, y: []f32) #no_bounds_check { … simd.fused_mul_add(simd.f32x8(a), xv, yv) … }
```
- `core:simd`: types `u8x16 … f32x8 … f64x8`, `add/sub/mul/div`, `min/max/clamp/abs`, `lanes_eq/lt/…` (masks are
  all-ones ints), `select`, `shuffle`, `swizzle`, `gather/scatter`, `masked_load/store`, `reduce_add_bisect/_ordered/
  _pairs`, `reduce_min/max/and/or/any/all`, `extract/replace`, `fused_mul_add`, `sqrt/floor/ceil`, `to_array`,
  `from_array`, `from_slice`, `simd.HAS_HARDWARE_SIMD`. Platform specifics: `core:simd/x86` (SSE…AVX-512 intrinsics),
  `core:simd/arm` (NEON, AES, SHA, CRC32, PMULL).
- Measured (4 Mi f32 sum, `-o:speed`, 8 lanes): M2 Max 7.2 ms → 1.2 ms; Core Ultra 9 1.9 ms → 0.65 ms (0.53 ms with
  `-microarch:native`); Orin 3.8 ms → 1.1 ms. Scalar float sums don't auto-vectorize (ordering), so explicit
  `#simd` pays off.
- `base:intrinsics` worth knowing: `prefetch_read_data(ptr, locality)`, `expect(v, expected)` (branch hints),
  `@(cold)` on error paths, `unaligned_load/store`, `non_temporal_store`, `mem_copy_non_overlapping`, `count_ones/
  count_leading_zeros/trailing`, `overflow_add` etc., `read_cycle_counter`, `cpu_relax`, `atomic_*_explicit`,
  `volatile_load/store`, `type_*` predicates for `where` clauses.
- Global: `-microarch:native` only for the machine you run on; ship with an explicit `-microarch:x86-64-v3` (or
  similar) + runtime dispatch for hot procs.

## Code generation control

- `-o:speed` for release (`-o:aggressive` = more LLVM passes, measure it), `-o:size` for small binaries,
  `-lto:thin` (Linux, lld), `-no-bounds-check`/`-disable-assert` program-wide only after profiling; prefer
  `#no_bounds_check` on a proc or block and `#bounds_check` to re-enable.
- `#force_inline` / `#force_no_inline` on procs and at call sites (`#force_inline f(x)`); `@(cold)`; `proc
  "contextless"` drops the context pointer for tiny leaf procs; `-lifetime-markers` (with `-o:size+`) lets disjoint
  locals share stack.
- Inspect output: `-build-mode:asm` (`.S`) or `-build-mode:llvm-ir -out:dir/`, or objdump the binary.

## Profiling and benchmarking

- **Spall** (`core:prof/spall`, viewer: gravitymoth.com/spall): manual scopes
  `spall.SCOPED_EVENT(&ctx, &buf, #procedure)`, or automatic whole-program instrumentation by defining
  `@(instrumentation_enter)` / `@(instrumentation_exit)` procs (signature `proc "contextless" (proc_address,
  call_site_return_address: rawptr, loc: runtime.Source_Code_Location)`) calling `spall._buffer_begin/_buffer_end`
  — there is no compiler flag: defining them instruments every proc with a body, except files with
  `#+no-instrumentation` and procs with `@(no_instrumentation)`. Example in `core/prof/spall/doc.odin`; validated
  manual scopes write a `.spall` file. Use a `@(thread_local)` `spall.Buffer` per thread.
- Sampling profilers on `-o:speed -debug` builds: Linux `perf record -g ./app` + `perf report`, macOS Instruments
  (`xcrun xctrace record --template 'Time Profiler' --launch -- ./app`), Windows Superluminal/VTune; Tracy through
  community bindings (odin-tracy).
- Microbenchmarks: `core:time` `tick_now/tick_since/tick_diff`, `time.Stopwatch`, `time.benchmark(&options)`
  (setup/bench/teardown callbacks; reports `rounds_per_second`, `megabytes_per_second`). Warm up, repeat, report
  medians, keep inputs live (write results somewhere) so LLVM doesn't delete the work. Compare A/B at the same
  `-o:` and `-microarch:` (experiment-design for stats).
