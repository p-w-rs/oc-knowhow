// Iprof: an instrumenting, hierarchical profiler that ships as a metaprogram plugin.
//   jai main.jai +Iprof                    instrument procedures with >= 30 expressions in the main program
//   jai main.jai +Iprof -min_size 1        instrument (almost) everything in the main program
//   jai main.jai +Iprof -modules           also instrument modules
//   jai main.jai +Iprof -csv profile.csv   also write the report as CSV (at RUN time, overwritten each run)
// The plugin wraps procedures in zones and injects startup into main; when main returns it logs a
// report (via context.logger) with self time, hierarchical time and call counts, for all threads,
// threads without the first, and each thread (per-thread since 0.2.031, MAX_THREADS = 256).
// Not instrumented: #c_call / #no_context procedures, polymorphic procedures, macros, procedures
// with a @NoProfile note. Timing uses System.read_cpu_counter: rdtsc on x64; on arm64 Unix only the
// nanoseconds field of clock_gettime (wraps every second, so long zones can come out wrong, even
// negative, on a Mac). Prefer -od builds for profiling (keeps stack traces, optimizes).
// JAI-ARGS: +Iprof -min_size 1
// EXPECT-CONTAINS: Starting Profiling.
// EXPECT-CONTAINS: result 2923100065
// EXPECT-CONTAINS: All Threads
// EXPECT-CONTAINS: self (ms)
// EXPECT-CONTAINS: heavy_part
// EXPECT-CONTAINS: light_part
// EXPECT-CONTAINS: frame
// EXPECT-COMPILE: [Iprof] Skipping 'skipped_helper' due to NoProfile note.
#import "Basic";

heavy_part :: (n: int) -> int {
    s := 0;
    for 1..n s += (it * it) % 1000;
    return s;
}

light_part :: (n: int) -> int {
    s := 0;
    for 1..n s += it;
    return s;
}

skipped_helper :: (x: int) -> int { return x + 1; } @NoProfile   // excluded by the note (Iprof logs that at compile time)

frame :: (i: int) -> int {
    return heavy_part(200_000) + light_part(20_000) + skipped_helper(i);
}

main :: () {
    total := 0;
    for 1..10 total += frame(it);
    print("result %\n", total);
}
