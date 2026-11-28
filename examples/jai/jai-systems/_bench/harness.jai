// Shared by the benchmarks in this folder (each one does #load "harness.jai").
// measure() runs the body once untimed (warm-up: caches, TLB, page faults), then `runs` more times
// and reports the median and the fastest run. Every kernel returns or updates a checksum that
// the program prints, so the optimizer cannot drop the work.
#import "Basic";
#import "Sort";

MAX_RUNS :: 15;
runs  := 7;
quick := false;            // "quick" on the command line: 3 runs and smaller sizes, for testing

// Takes "quick" out of the arguments and returns the rest (without the program name).
parse_common_args :: () -> [] string {
    rest: [..] string;
    for get_command_line_arguments() {
        if it_index == 0 continue;
        if it == "quick" { quick = true; runs = 3; continue; }
        array_add(*rest, it);
    }
    return rest;
}

Timing :: struct {
    median_ns: float64;    // of the timed runs
    min_ns:    float64;
}

measure :: (body: Code) -> Timing #expand {
    samples: [MAX_RUNS] s64;
    #insert body;
    for r: 0..runs-1 {
        t0 := current_time_monotonic();
        #insert body;
        samples[r] = to_nanoseconds(current_time_monotonic() - t0);
    }
    return summarize(samples, runs);
}

summarize :: (samples: [MAX_RUNS] s64, count: int) -> Timing {
    sorted: [MAX_RUNS] s64 = samples;
    view := array_view(sorted, 0, count);
    quick_sort(view, (a: s64, b: s64) -> s64 { return ifx a < b then -1 else ifx a > b then 1 else 0; });
    return .{median_ns = cast(float64) view[count / 2], min_ns = cast(float64) view[0]};
}

// Divides a whole-run timing by the number of operations in one run.
per_op :: (t: Timing, operations: s64) -> Timing {
    return .{t.median_ns / operations, t.min_ns / operations};
}

// Three significant digits are plenty for timings that move by a few percent between runs.
number :: (x: float64) -> string {
    if x < 10  return tprint("%", formatFloat(x, trailing_width = 2, zero_removal = .NO));
    if x < 100 return tprint("%", formatFloat(x, trailing_width = 1, zero_removal = .NO));
    return tprint("%", formatFloat(x, trailing_width = 0));
}

// A table cell: "median (min)".
cell :: (t: Timing) -> string {
    return tprint("% (%)", number(t.median_ns), number(t.min_ns));
}

print_table_header :: (first: string, columns: [] string) {
    print("| % |", first);
    for columns print(" % |", it);
    print("\n|---|");
    for columns print("---|");
    print("\n");
}

// Fisher-Yates shuffle with the Random module's context generator.
// Careful: a reverse loop is written `for < i: low..high` (it counts from high down to low);
// `for < i: high..low` runs zero times.
shuffle :: (values: [] $T) {
    for < i: 1..values.count-1 {
        j := cast(s64) (random_get() % cast(u64) (i + 1));
        values[i], values[j] = values[j], values[i];
    }
}

#import "Random";
