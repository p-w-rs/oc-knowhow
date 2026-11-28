# Profiling Jai programs (deep dive)

Verified on Jai beta 0.2.032 (macOS arm64 M2 Max; Linux x86-64 powerslabs and ubuntu-laptop). Example:
`examples/jai/jai-systems/40_iprof.jai`. Sources: `modules/Iprof/` (`module.jai`, `instrument.jai`, `options.jai`,
`runtime.jai`, `reports.jai`), `modules/Performance_Report.jai`, `modules/System.jai` (`read_cpu_counter`),
`modules/telemetry3/`. Library: `library_search query="Iprof min_size csv" sources=["jai-modules-src"]`.

Order of attack: measure the whole program first (wall time of `-o` builds, several runs), then a sampling profiler
(no code changes, true costs), then Iprof (exact call counts and hierarchical times, but overhead per call), then
targeted timing with `current_time_monotonic()` around the suspect code (reference/performance.md).

## Iprof: instrumenting profiler as a metaprogram plugin

- Run: `jai main.jai +Iprof` (plugins go last on the command line, each `+Name` takes the arguments up to the next
  `+`; the old `-plug Iprof` is "Unknown argument" since 0.2.012). Options:
  `-min_size n` instrument only procedures with at least n expressions (default 30, so small helpers are skipped;
  `-min_size 1` for almost everything), `-modules` (also instrument modules; Iprof, Pool and Atomics never, Basic and
  Thread through a guarded variant), `-csv file` (write a CSV report when the program ends; the name is fixed at
  compile time, the file is rewritten at every run). Help: `jai -help +Iprof` prints the plugin's options after the
  compiler's (run it in a terminal or through `script`, help goes only to a terminal).
- What it does: at compile time it intercepts typechecked procedure bodies and inserts a zone at the top of each
  selected one (`context._Iprof.Automatic_Zone(n)`, a macro with a `defer`), adds `#add_context _Iprof` and
  `already_inside_profiler_runtime`, and wraps `main` with startup and a final report. Compile output lists what it
  did: `[Iprof] Adding the zone initialization code for 5 zones.` and `[Iprof] Skipping 'name' due to NoProfile note.`
- Not instrumented: `#c_call` / `#no_context` procedures (no context to find the profiler), polymorphic procedures,
  macros, compiler-generated and compile-time-only procedures, procedures with a `@NoProfile` note
  (`f :: () {...} @NoProfile`; the note was ignored before 0.2.031).
- Output (logged through `context.logger` when `main` returns; real run, Mac, `-min_size 1`):

```
Starting Profiling.
total -1872077397563914234
All Threads               self (ms)   hier (ms)   calls
slow_sum                     37.844      37.844      20
fast_sum                      5.113       5.113      20
main                          0.020      42.989       1
frame                         0.013      42.969      20

Threads w/o first         self (ms)   hier (ms)   calls

Thread 0                  self (ms)   hier (ms)   calls
slow_sum                     37.844      37.844      20
...
```

  `self` = time in the procedure minus its instrumented children; `hier` = including children; `calls` = entries.
  Since 0.2.031 it profiles every thread whose `context.thread_index < MAX_THREADS` (module parameter, 256) and prints
  one section per thread after the "All Threads" and "Threads w/o first" sections.
- CSV (`-csv prof.csv`), real file:

```
! Instrumented by: ["/Users/you/jai/current/bin/jai-macos", "prof.jai", "-quiet", "+Iprof", "-min_size", "1", "-csv", "prof.csv"]
name,self (ms),hier (ms),calls
slow_sum,36.99905,36.99905,20
fast_sum,4.98903,4.98903,20
(global),0.34541,42.35949,0
main,0.01538,42.01408,1
frame,0.01063,41.99871,20
```

- **Overhead** (measured on powerslabs, recursive `fib(27)` = 635621 calls): `-o` 0.8 ms → 22.7 ms with
  `+Iprof -min_size 1` (≈ 34 ns per instrumented call); debug 1.6 → 39.5 ms. Tiny, hot procedures are distorted badly:
  keep the default `-min_size 30` (or larger) and add `@NoProfile` to small hot helpers; trust ratios between big
  procedures, not absolute numbers of small ones.
- **Clock caveat:** zones read `System.read_cpu_counter()`. On x64 that is `rdtsc`; on arm64 macOS/Linux it is only the
  nanoseconds field of `clock_gettime`, which wraps every second. On the Mac one run reported `main` with a self time of
  −0.223 ms; zones longer than a second are unreliable. Profile with Iprof on x64 Linux when you can.
- Modes: `IMPORT_MODE` (`.METAPROGRAM` for the plugin side, `.CLIENT` for the runtime side, which the plugin imports
  for you), `MANUAL_MODE` (place zones yourself with the runtime's `zone_begin(index)`/`zone_end()`; up to 2048 zones;
  not exercised here), `USE_GRAPHICS` / `DO_HISTORY` (an interactive in-game view via `draw.jai` and per-frame history:
  call the per-frame hook; not exercised here).

## Performance_Report: what the compiler spends time on

`jai main.jai +Performance_Report` prints, after compiling: a time report (#run execution, bytecode inlining,
bytecode generation), a #run report (each `#run` call site with elapsed time and stalls), a polymorph report (each
polymorphic procedure with call sites, how many polymorphs and deduplications, e.g. `min [Basic/module.jai:222,8]
6 call sites, 5 constants_dedup ... 1 polymorph: (T=s64)`) and a bytecode report (calls and instructions inlined vs
total). Use it to cut compile time (polymorph explosion, slow `#run`), not run time.

## Sampling profilers on Jai executables

Debug builds have full symbols and line tables (macOS: a `.dSYM` next to the executable; Linux: DWARF in the ELF).
Procedure symbols get a hex suffix (`hot_inner_9000000c0`); `main` is `__program_main`; the C entry is
`__system_entry_point_*` in Runtime_Support. `-od` and `-o` inline small procedures into their callers, so the
profile collapses onto the caller (the `-od` run of the example below showed only `__program_main hot.jai:14`).

### macOS

- `sample <pid> <seconds> -file out.txt` (no root needed for your own processes; start the program, then sample it):

```
Call graph:
    811 Thread_8552934   DispatchQueue_1: com.apple.main-thread  (serial)
      811 start  (in dyld) + 6992  [0x1867044e4]
        811 __system_entry_point_d00000350  (in hot) + 184  [0x1021d0ec0]  Runtime_Support.jai:446
          811 __program_main  (in hot) + 236  [0x1021ccffc]  hot.jai:14
            811 cold_outer_9000000c1  (in hot) + 208  [0x1021ccbd8]  hot.jai:9
              811 hot_inner_9000000c0  (in hot) + 168,96,...  [0x1021cc4f0,0x1021cc4a8,...]  hot.jai:4
...
Sort by top of stack, same collapsed (when >= 5):
        hot_inner_9000000c0  (in hot)        811
```

- Instruments from the command line: `xcrun xctrace record --template 'Time Profiler' --time-limit 3s --output
  hot.trace --launch -- ./hot` (records until the program exits), then `xcrun xctrace export --input hot.trace --toc`
  and `xcrun xctrace export --input hot.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'
  > tp.xml`. The XML has one row per sample (1022 rows for 1.9 s) with backtraces; Jai frames are named
  (`hot_inner_9000000c0`, `cold_outer_9000000c1`, `__program_main`), many other frames appear as raw addresses.
  Open `hot.trace` in Instruments for the GUI. xctrace 27.2 worked without extra permissions for a launched process.

### Linux

- `perf record -g ./prog` / `perf stat ./prog` need `kernel.perf_event_paranoid` ≤ 2 or CAP_PERFMON. Both machines
  here had 3 and 4 (perf refused: "Failure to open any events for recording"); changing it needs root (`sysctl
  kernel.perf_event_paranoid=1`). Not done here.
- Valgrind's callgrind needs no privileges (≈ 50× slowdown; use smaller inputs):
  `valgrind --tool=callgrind --callgrind-out-file=cg.out ./hot` then `callgrind_annotate cg.out`. Real output
  (powerslabs, debug build): the function table shows `400,001,900 (99.97%)  hot.jai:hot_inner_90000016e`, and the
  auto-annotated source gives instruction counts per line of the `.jai` file:

```
        500 ( 0.00%)  hot_inner :: (n: int) -> int {
        100 ( 0.00%)      s := 0;
400,000,800 (99.96%)      for 1..n { s += (it * it) % 7; s ^= it; }
        400 ( 0.00%)      return s;
```

  `valgrind --tool=cachegrind --cache-sim=yes --cachegrind-out-file=cachegrind.out ./hot` + `cg_annotate
  cachegrind.out` works the same way (verified: per-function and per-line instruction, data-read and cache-miss counts
  on `hot.jai`). Memcheck, by contrast, did not start on this Arch machine (see reference/debugging.md). Valgrind is
  x86-64 Linux only here; there is none on macOS arm64.

## Tracy and Telemetry

- No Tracy binding ships with the compiler. Options: the community binding rluba/jai-tracy (MIT; not built here), or
  the C route: build Tracy's `TracyClient.cpp` with `-DTRACY_ENABLE` into a static or shared library and declare the
  `___tracy_*` functions from `TracyC.h` with `#foreign` (zone begin/end take a `___tracy_source_location_data`
  pointer and return a context struct). Untested here; c-perf documents the Tracy side (capture, csvexport, version
  matching).
- `modules/telemetry3`: bindings for RAD Game Tools' Telemetry, a commercial profiler; the bundle only contains
  Windows DLLs (`win/rad_tm_win64.dll`). Requires a Telemetry license and server: documented only.

## Hand instrumentation

For a few zones, `current_time_monotonic()` before/after and `to_nanoseconds` are enough (Apollo_Time arithmetic).
For per-frame statistics keep samples in a fixed array and report medians and percentiles; don't print inside the
measured region. A tiny RAII-style zone is a macro with a backtick `defer`:

```jai
Timed :: (label: string) #expand {
    `__t0 := current_time_monotonic();
    `defer print("% took % us\n", label, to_microseconds(current_time_monotonic() - `__t0));
}
work :: () { Timed("work"); /* ... */ }
```

(`to_microseconds` returns `(value, success)`; print shows the first.) Compiled and run on the Mac: "work took 3489
us" for a debug-build loop of 1M additions. Basic's `auto_release_temp` and `push_allocator` use the same
backtick-defer idea.
