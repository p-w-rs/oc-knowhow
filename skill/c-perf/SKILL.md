---
name: c-perf
description: Profiling and memory allocators for C, C++ and Odin programs — Tracy 0.15 (TracyClient.cpp, TRACY_ENABLE, C++ ZoneScoped/FrameMark/TracyAlloc/TracyLockable and C TracyCZone*/TracyCFrameMark/TracyCPlot/TracyCMessage/TracyCAlloc/TracyCLock* macros, on-demand and short-lived programs, ports, headless capture with tracy-capture/tracy-capture-daemon and text results with tracy-csvexport so agents can read zone statistics, the GUI, odin-tracy bindings), mimalloc v3 (static vs override builds, LD_PRELOAD/DYLD_INSERT_LIBRARIES, MIMALLOC_* options, first-class heaps and theaps, stats), rpmalloc 2.0 (auto-init, thread init, first-class heaps, statistics) and measured multithreaded allocator benchmarks on macOS and Linux, plus Odin allocators (heap vs a mem.Allocator wrapping mimalloc vs mimalloc heaps vs vmem and mem arenas). Load before profiling native code, choosing or swapping a malloc, or writing an allocator benchmark.
---

# Native performance: Tracy, mimalloc, rpmalloc

## Ground truth first

- Versions as of Nov 2026 (verify): **Tracy v0.15.0** (2026-11-05), **mimalloc v3.6.1** (2026-10-30; v2 line at v2.5.2),
  **rpmalloc 2.0.1** (2026-07), **oskarnp/odin-tracy** at 307845d (written for Tracy 0.14.1). conda-forge has
  `mimalloc 3.6.1` and `tracy-profiler 0.14.1` (GUI) but **not 0.15**, and no rpmalloc. Client and server must be the
  **same Tracy version** (the protocol changes; NEWS says breakages aren't listed), so build the capture tools from the
  same tag as `TracyClient.cpp`.
- Reference library: `tracy-source` (public/ client headers, manual/tracy.tex, NEWS), `mimalloc-source` (include/,
  docs), `rpmalloc-source` (rpmalloc/rpmalloc.h, README). Use `library_search query="TracyCZoneN"
  sources=["tracy-source"]` for exact macro definitions. The manual (tracy.tex) is the authority on options.
- Toolchain from Pixi: `pixi add c-compiler cxx-compiler cmake ninja` (see pixi). For Odin-specific profiling (spall,
  instrumentation procs) and allocator design see odin-performance. For statistics on benchmark results (repeats,
  intervals) see stats-inference and experiment-design.

## Tracy: instrument

- Client = one C++ file: `c++ -std=c++17 -O2 -DTRACY_ENABLE -c tracy/public/TracyClient.cpp` (3 s) and link it into
  the app (link with `c++` plus `-lpthread`; older glibc may also need `-ldl`). **Define `TRACY_ENABLE` for every TU** that includes
  Tracy headers; without it every macro compiles to nothing, which is how you ship.
- C++ (`#include "tracy/Tracy.hpp"`): `ZoneScoped;` / `ZoneScopedN("name");` / `ZoneScopedNC("name", 0xff8000);`,
  `ZoneText(str, len)`, `ZoneValue(v)`, `FrameMark;` (end of frame) / `FrameMarkNamed("physics")`,
  `TracyPlot("bytes", v)`, `TracyMessageL("literal")`, `TracyAlloc(p, n)` / `TracyFree(p)` (or `…N` named pools; the
  "Secure" variants were removed in 0.14), locks `TracyLockable(std::mutex, m)` + `LockMark(m)`,
  `TracySharedLockable`. **0.15: all macros must end with a semicolon.**
- C (`#include "tracy/TracyC.h"`), validated in `tracy_c.c`:
  ```c
  TracyCZoneN(z, "work", 1); … TracyCZoneValue(z, n); TracyCZoneEnd(z);    /* also TracyCZoneNC(ctx, name, color, active) */
  TracyCZoneTextF(z, "n=%d", n);                       /* printf variants since 0.14 */
  TracyCFrameMark;  TracyCPlot("frame bytes", v);  TracyCMessage(buf, len);  TracyCMessageL("literal");
  TracyCAllocN(p, size, "frame buffers"); TracyCFreeN(p, "frame buffers");   /* emit BEFORE free() */
  TracyCSetThreadName("worker 1");  TracyCAppInfo("demo", 4);  if (TracyCIsConnected) …
  TracyCLockCtx l; TracyCLockAnnounce(l); TracyCLockCustomName(l, "shared_sum", 10);
  TracyCLockBeforeLock(l); pthread_mutex_lock(&m); TracyCLockAfterLock(l);
  TracyCLockBeforeUnlock(l); pthread_mutex_unlock(&m);                  /* 0.15 rename: was AfterUnlock, now BEFORE the unlock */
  ```
  Every zone begin needs its End on all paths (early returns!). Keep zone granularity above ~100 ns: each event costs
  a few ns plus queue bandwidth.
- Build-time options (manual table "cmakeoptions"): `TRACY_ON_DEMAND` (collect only while a server is connected; use
  it when you keep instrumentation in shipped builds), `TRACY_NO_EXIT` (the process waits at exit until the data is
  sent; also an env var `TRACY_NO_EXIT=1`; useful for short-lived tools), `TRACY_ONLY_LOCALHOST` (define or env),
  `TRACY_NO_BROADCAST`, `TRACY_PORT` / `TRACY_DATA_PORT` / `TRACY_BROADCAST_PORT` (env `TRACY_PORT` changes the data port
  at runtime; default 8086), `TRACY_CALLSTACK=<depth>`, `TRACY_NO_SAMPLING`, `TRACY_NO_SYSTEM_TRACING`,
  `TRACY_MANUAL_LIFETIME` + `TRACY_DELAYED_INIT` (`___tracy_startup_profiler()` / `___tracy_shutdown_profiler()`;
  needed when the client lives in a dylib that is unloaded). The client listens on all interfaces by default, so
  remote capture works from another machine, but it also means anyone on the network can connect: use ONLY_LOCALHOST
  plus an ssh tunnel (`ssh -L 8086:localhost:8086 host`).
- GPU zones: `TracyGpuContext`/`TracyGpuZone` (OpenGL) and per-API headers in `tracy/`: TracyVulkan, TracyD3D11/12,
  TracyMetal.hmm, TracyCUDA, TracyOpenCL, TracyWebGPU. Not validated here.

## Tracy: capture headless and read results as text

- Build the tools from the same tag (CMake fetches capstone, zstd, PPQSort and nlohmann/json through CPM on first
  configure; set `CPM_SOURCE_CACHE` to keep them):
  ```bash
  export CPM_SOURCE_CACHE=$PWD/.cpm
  cmake -S tracy/capture   -B build-cap -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-cap   # tracy-capture, tracy-capture-daemon
  cmake -S tracy/csvexport -B build-csv -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-csv   # tracy-csvexport
  ```
  Both built with conda-forge clang on macOS. Other tools in the repo: `merge/` (tracy-merge, 0.14+), `import/`
  (chrome/fuchsia JSON → .tracy), `update/` (upgrade old traces), `monitor/` (0.15, Linux: sampling profile of an
  uninstrumented program), `profiler/` (GUI, needs a display; 0.15 downloads pandoc at build time).
- Capture (validated, same machine): start the capture first, then the app:
  ```bash
  ./build-cap/tracy-capture -o run.tracy -a 127.0.0.1 -f -s 20 &   # -f overwrite, -s seconds limit, -m memlimit, -p port
  ./app            # client connects, streams; capture prints "Frames: 62  Time span: 534.1 ms  Zones: 600 … Saving trace... done!"
  ```
  The client buffers events from startup until a server connects (unless ON_DEMAND), so starting capture slightly
  later still records everything, but the process must outlive the transfer (`TRACY_NO_EXIT=1` for short runs).
  `tracy-capture-daemon -o dir` (0.14+) listens for client UDP broadcasts on 8086 and captures every client into
  `dir` automatically (filters `--filter-name`, `--filter-port`); good for CI.
- Text output for agents (`tracy-csvexport run.tracy`), real output:
  ```
  name,src_file,src_line,total_ns,total_perc,counts,mean_ns,min_ns,max_ns,std_ns
  job,tracy_c.c,27,7036381,1.317426,240,29318,18500,92542,7853.221294
  work,tracy_c.c,14,6905173,1.292860,287,24059,41,92125,12742.540749
  main frame,tracy_c.c,52,271000,0.050739,60,4516,1291,38166,5296.198640
  ```
  `-e` self time (here `job` self = 134708 ns: the child `work` is the cost), `-f name` filter (`-c` case-sensitive),
  `-u` one row per zone event (`name,src_file,src_line,ns_since_start,exec_time_ns,thread,value`), `-u -p` plot
  samples, `-m` messages with timestamps, `-F` frame statistics (`frame_set,…,median_ns,…,p99_ns`; add `-S` per
  section), `-g` GPU zones, `-t[=90]` truncated mean, `-s ';'` separator. Sort or aggregate with any CSV tool; plot
  with gnuplot.
- Pitfall seen: `work` min 41 ns, because the compiler removed a call whose result was unused, leaving an empty zone.
  Keep benchmark results live. The first frame includes the wait for the connection (p99 205 ms against a 5 ms median),
  so drop warm-up frames.

## Tracy from Odin

- **oskarnp/odin-tracy** (BSD-3): `import tracy "odin-tracy"`, build the client as a shared library next to the
  package: macOS `c++ -std=c++17 -DTRACY_ENABLE -O2 -dynamiclib tracy/public/TracyClient.cpp -o tracy.dylib
  -install_name @rpath/tracy.dylib`, Linux `… -shared -fPIC -o tracy.so` (the repo's `build_*.sh` do this from its
  tracy submodule, so clone with `--recurse-submodules`, or point them at your own Tracy checkout). Build the app
  with `odin build . -define:TRACY_ENABLE=true` (without it all procs are `@(disabled)`).
- Validated with the **0.15 client** and capture: `tracy.Zone()` (deferred: ends at scope exit), `tracy.ZoneN("update")`,
  `tracy.ZoneNC("render", 0xff8000)`, `tracy.ZoneValue(ctx, v)`, `tracy.FrameMark()`, `tracy.Plot(name, f64)`,
  `tracy.MessageS(str)`, `tracy.SetThreadName(cstr)`, `tracy.IsConnected()`,
  `context.allocator = tracy.MakeProfiledAllocator(self = &tracy.ProfiledAllocatorData{}, backing_allocator =
  context.allocator)` (memory events; Free_All not reported). Capture: 60 frames, 297 zones; csvexport lists `fib`,
  `worker job`, `update`, `render` with full Odin source paths. Zones allocate a source location at runtime per call
  (`___tracy_alloc_srcloc_name`), which is a bit more overhead than C's static ones.
- Pitfalls: Odin executables get `LC_RPATH @loader_path`, so put `tracy.dylib` next to the executable or set
  `DYLD_LIBRARY_PATH` (else `dyld: Library not loaded: @rpath/tracy.dylib`). The bindings still declare the 0.14
  `___tracy_after_unlock_*_lockable_ctx` procs: unused foreign procs aren't linked, so it builds, but calling them
  against 0.15 gives an undefined symbol (0.15 has `___tracy_before_unlock_*`). Fix the binding before using locks.
  Without the bindings, `foreign import` a static `TracyClient.o` archive (+ `system:c++`) and declare the
  `___tracy_*` C functions from TracyC.h yourself.

## mimalloc (v3)

- Two ways in: **API** (`mi_malloc`/`mi_free`/`mi_heap_*`, build with `-DMI_OVERRIDE=OFF`) or **override** (default
  `MI_OVERRIDE=ON`: link `libmimalloc` first, or preload the shared lib into an unmodified binary:
  `LD_PRELOAD=/path/libmimalloc.so ./app`, macOS `DYLD_INSERT_LIBRARIES=/path/libmimalloc.dylib ./app`; SIP-protected
  system binaries ignore it). conda-forge `mimalloc` gives the shared library for preload; cmake from source:
  `cmake -S mimalloc -B b -G Ninja -DCMAKE_BUILD_TYPE=Release -DMI_BUILD_TESTS=OFF` → `libmimalloc.{a,so|dylib}`
  (`-DMI_BUILD_SHARED=OFF -DMI_OVERRIDE=OFF` for an API-only static lib, as used in the benchmarks below). Version check
  `mi_version()` → 30601.
- Env options (`MIMALLOC_<OPTION>`, or `mi_option_set` in code): `MIMALLOC_VERBOSE=1` (prints `v3.6.1, release` and
  every option at startup, a quick way to confirm the preload took effect), `MIMALLOC_SHOW_STATS=1` (stats at exit:
  per-size-bin table plus `process: user, system, faults, peak rss, peak commit`), `MIMALLOC_SHOW_ERRORS`,
  `MIMALLOC_PURGE_DELAY` (ms, default 10; 0 = return memory immediately, -1 = never), `MIMALLOC_ALLOW_LARGE_OS_PAGES`,
  `MIMALLOC_RESERVE_HUGE_OS_PAGES=N` (1 GiB pages), `MIMALLOC_ARENA_EAGER_COMMIT`. Env vars do nothing if the process
  doesn't actually load mimalloc. In code: `mi_stats_print(NULL)`, `mi_collect(true)`, `mi_process_info(…)`.
- Heaps (validated): `mi_heap_t *h = mi_heap_new(); p = mi_heap_malloc(h, n);` (also `_zalloc`, `_malloc_aligned`) →
  `mi_heap_destroy(h)` frees **all** its blocks at once (arena-like, per level/request) or `mi_heap_delete(h)`
  moves live blocks to the main heap. `mi_free` works on blocks from any heap and from any thread. v3 adds **theaps**
  (`mi_heap_theap`, `mi_theap_set_default`, `mi_theap_malloc`): thread-local heaps that are a little faster and can be
  made the default for plain `malloc` on that thread. Aligned API: `mi_malloc_aligned`, `mi_zalloc_aligned`,
  `mi_realloc_aligned`, `mi_usable_size` (210 B request → 224 usable).

## rpmalloc (2.0)

- Add `rpmalloc/rpmalloc.c` + `rpmalloc.h`. By default (`ENABLE_OVERRIDE=1`) it **includes malloc.c and replaces
  malloc/free/new/delete**; compile with `-DENABLE_OVERRIDE=0` to use only `rpmalloc()/rpfree()/rprealloc()/
  rpaligned_alloc()`. Auto-initializes on first use, and threads auto-init with thread destructors; call
  `rpmalloc_initialize(NULL)` / `rpmalloc_initialize_config(&iface, &cfg)` first if you want a custom memory
  interface or config (huge pages, page name, unmap on finalize), and `rpmalloc_thread_finalize()` on threads you
  manage yourself. With a static library and only libc entry points, call `rpmalloc_linker_reference()` once so the
  overrides get linked.
- First-class heaps need `-DRPMALLOC_FIRST_CLASS_HEAPS=1` (both for rpmalloc.c and your TU):
  `rpmalloc_heap_acquire()`, `rpmalloc_heap_alloc(h, n)`, `rpmalloc_heap_free_all(h)`, `rpmalloc_heap_release(h)`.
  A heap is used from one thread at a time. Statistics need `-DENABLE_STATISTICS=1`
  (`rpmalloc_global_statistics(&s)`: `mapped`, `mapped_peak`, `committed`; `rpmalloc_dump_statistics(stdout)`), and
  report zeros otherwise.

## Measured: multithreaded C allocator benchmark

`alloc_bench.c`: each thread runs 40 rounds × 250k (free a random slot of 4096 + allocate a new block; 90% 16–256 B,
9% 256–4096 B, 1% 4–64 KiB; touch first and last byte). The slot arrays rotate between threads each round, so frees are
cross-thread. Median of 3 runs, M ops/s in total (peak RSS).

| threads | system malloc | mimalloc 3.6.1 (API) | rpmalloc 2.0.1 | system binary + mimalloc preload |
|---|---|---|---|---|
| **macOS M2 Max** 1 | 22.9 (12 MiB) | 99.3 (11) | 120.4 (12) | 84.5 (11) |
| 4 | 25.8 (42) | 315.0 (45) | 359.1 (43) | 276.6 (41) |
| 8 | 34.9 (**599**) | 411.9 (80) | 486.8 (89) | 374.0 (80) |
| 12 | 35.9 (**1819**) | 383.9 (138) | 435.5 (147) | 405.7 (128) |
| **Linux Core Ultra 9 285K, glibc 2.44** 1 | 67.1 (7) | 135.8 (20) | 142.6 (9) | 126.1 (18) |
| 8 | 204.5 (46) | 610.8 (122) | 751.3 (65) | 668.7 (122) |
| 16 | 420.5 (88) | 902.2 (221) | 1369.8 (132) | 898.0 (210) |
| 24 | 569.4 (135) | 985.2 (335) | 1651.3 (199) | 959.1 (320) |

- macOS libmalloc doesn't scale with cross-thread frees and its RSS explodes (1.8 GiB against ~130 MiB). On macOS, swapping
  the allocator is the single biggest win for allocation-heavy multithreaded code. glibc scales but stays 2–3× behind.
- rpmalloc was fastest in this workload; on Linux mimalloc held 2–3× the RSS of glibc (122–335 vs 46–135 MiB) and
  rpmalloc ~1.5×. Preloading
  mimalloc gets most of the gain with zero code changes. Measure your own pattern: allocator rankings flip with size
  distribution and producer/consumer frees (mimalloc-bench, rpmalloc's BENCHMARKS.md). Report medians of repeated runs
  and peak RSS, not just throughput.

## Measured: Odin allocators

`odin_alloc/main.odin` (dev-2026-11a, `-o:speed`): per thread, 60 frames × 50k `mem.alloc_bytes_non_zeroed`
(16–1024 B, 1% up to 16 KiB) plus a growing `[dynamic]int`; then free every block (Heap, Mi) or `free_all` (others).
Best of 3, M allocs/s (alloc + free included).

| allocator | Mac 1 thr | Mac 8 | Mac 12 | Linux 1 | Linux 8 | Linux 24 |
|---|---|---|---|---|---|---|
| `runtime.heap_allocator` (libc malloc + align header) | 16.4 | 34.5 | 37.1 | 4.7 | 21.6 | 32.2 |
| mimalloc as `mem.Allocator` (below) | 43.1 | 132.8 | 140.2 | 29.3 | 124.8 | 142.6 |
| mimalloc heap per thread, `free_all` = destroy + new | 50.7 | 152.3 | 149.7 | 32.2 | 155.4 | 198.8 |
| `vmem.arena_init_growing` (1 MiB first block) | 15.7 | 49.5 | 48.2 | 5.3 | 10.1 | 11.0 |
| `vmem` growing with 64 MiB first block | 28.2 | 93.4 | 105.2 | 16.7 | 61.4 | 69.6 |
| `vmem.arena_init_static` (1 GiB reserve) | 29.5 | 92.9 | 105.6 | 16.3 | 60.9 | 70.8 |
| `mem.Arena` over `make([]byte, 64 MiB)` | **73.4** | **306.1** | **304.1** | 34.1 | 143.6 | **203.7** |

- Why the vmem arenas lose (from `core/mem/virtual/arena.odin`): every `arena_alloc` takes a mutex, and `free_all`
  **zeroes the used memory** (growing: first block; static: `arena_static_reset_to`). On top of that, a growing arena
  frees all blocks but the first, so a frame larger than the first block means mmap/munmap every frame, which
  collapses under threads on Linux (10 M/s). `mem.Arena.free_all` is just `offset = 0`. For per-frame scratch: a
  `mem.Arena` over a buffer sized for the worst frame, or a vmem arena whose first block covers the frame, or a
  mimalloc heap when individual frees are also needed.
- Linux heap at 1 thread (171–211 ns/alloc) is glibc returning memory to the OS after each frame's frees:
  `GLIBC_TUNABLES=glibc.malloc.trim_threshold=1073741824:glibc.malloc.mmap_threshold=1048576` → 49 ns; `LD_PRELOAD`
  mimalloc under Odin's unchanged heap allocator → 26.6 M/s (1 thread) and 102 M/s (8 threads, vs 21.6).
- The mimalloc allocator proc (validated, `-vet -strict-style`):
  ```odin
  foreign import mimalloc "libmimalloc.a"          // API-only build; on Linux also "system:pthread"
  @(default_calling_convention = "c") foreign mimalloc {
      mi_malloc_aligned :: proc(size, alignment: uint) -> rawptr ---;  mi_zalloc_aligned :: proc(size, alignment: uint) -> rawptr ---
      mi_realloc_aligned :: proc(p: rawptr, newsize, alignment: uint) -> rawptr ---;  mi_free :: proc(p: rawptr) ---
  }
  mimalloc_allocator_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
                                  old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
      align := uint(max(alignment, 1))
      switch mode {
      case .Alloc, .Alloc_Non_Zeroed:
          p := mode == .Alloc ? mi_zalloc_aligned(uint(size), align) : mi_malloc_aligned(uint(size), align)
          if p == nil && size > 0 { return nil, .Out_Of_Memory }
          return ([^]byte)(p)[:size], nil
      case .Free: mi_free(old_memory); return nil, nil
      case .Resize, .Resize_Non_Zeroed:
          p := mi_realloc_aligned(old_memory, uint(size), align)
          if p == nil && size > 0 { return nil, .Out_Of_Memory }
          if mode == .Resize && size > old_size { mem.zero(rawptr(uintptr(p) + uintptr(old_size)), size - old_size) }
          return ([^]byte)(p)[:size], nil
      case .Query_Features:
          if s := (^mem.Allocator_Mode_Set)(old_memory); s != nil { s^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features} }
          return nil, nil
      case .Free_All, .Query_Info: return nil, .Mode_Not_Implemented
      }
      return nil, nil
  }
  ```
  Don't use `mi_rezalloc_aligned` for `.Resize`: it only zeroes correctly for blocks that were zero-allocated. The
  heap variant stores `^mi_heap_t` in `data`, uses `mi_heap_zalloc_aligned`/`mi_heap_malloc_aligned`, implements
  `.Free_All` as `mi_heap_destroy` + `mi_heap_new`, and `.Resize` via `mem.default_resize_bytes_align`.

## Workflow

1. Instrument coarse zones (frame, systems, jobs) and `FrameMark`, capture headless, read `tracy-csvexport -e`
   (self time) and `-F` (frame percentiles). Add finer zones only where the time is.
2. If malloc shows up (or the GUI memory view shows churn): try `LD_PRELOAD`/`DYLD_INSERT_LIBRARIES` mimalloc first
   (zero code change), then arenas/heaps per lifetime (odin-performance), then rpmalloc or mimalloc linked in.
3. Re-measure with the same build flags, several runs, medians plus peak RSS. Stop instrumented binaries and
   capture processes when done (`pkill tracy-capture`).
