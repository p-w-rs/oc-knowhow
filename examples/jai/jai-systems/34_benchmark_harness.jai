// A small benchmark harness: warm up, repeat, take the MEDIAN (and min) of several runs,
// keep results live (accumulate a checksum and print it) so the optimizer cannot drop the work.
// - current_time_monotonic() returns Apollo_Time; subtract and convert with to_float64_seconds,
//   to_nanoseconds, to_microseconds. (seconds_since_init() counts from its own FIRST call.)
// - System.read_cpu_counter() is rdtsc on x64 but only clock_gettime's nanosecond FIELD on arm64
//   Unix: it wraps every second there, so never use it for intervals on a Mac.
// - Compare builds with the same flags; build with -o (or -od) for meaningful numbers:
//   debug builds keep bounds checks and stack-trace bookkeeping (see reference/performance.md).
// Output here is only comparisons, so it is stable across machines.
// EXPECT: sum_squares checksum: 333333833333500000
// EXPECT: median <= max for every kernel: true
// EXPECT: inline (macro-like) and plain calls give the same result: true
// EXPECT: a reserved [..] does one allocation, a growing one 8: true
#import "Basic";
#import "Sort";

RUNS :: 7;

measure :: (body: Code) -> (median_ns: s64, max_ns: s64) #expand {
    samples: [RUNS] s64;
    #insert body;                                    // warm-up run (caches, page faults)
    for r: 0..RUNS-1 {
        t0 := current_time_monotonic();
        #insert body;
        samples[r] = to_nanoseconds(current_time_monotonic() - t0);
    }
    quick_sort(samples, (a: s64, b: s64) -> s64 { return a - b; });
    return samples[RUNS/2], samples[RUNS-1];
}

sum_squares :: (n: int) -> int {
    s := 0;
    for 1..n s += it * it;
    return s;
}

twice :: inline (x: int) -> int { return x * 2; }   // 'inline' on the declaration: always inlined
twice_call :: (x: int) -> int { return x * 2; }

growth_allocations :: (reserve: bool) -> int {
    allocations := 0;
    counting :: (mode: Allocator_Mode, size: s64, old_size: s64, old: *void, data: *void) -> *void {
        if mode == .ALLOCATE || mode == .RESIZE { (cast(*int) data).* += 1; }   // braces: see example 08
        return context.default_allocator.proc(mode, size, old_size, old, null);
    }
    a: [..] int;
    a.allocator = .{counting, *allocations};
    if reserve array_reserve(*a, 1000);
    for 1..1000 array_add(*a, it);
    array_free(a);
    return allocations;
}

main :: () {
    checksum := 0;
    med1, max1 := measure(#code { checksum += sum_squares(1_000_000); });
    print("sum_squares checksum: %\n", checksum / (RUNS + 1));

    acc_inline, acc_call := 0, 0;
    med2, max2 := measure(#code { for 1..100_000 acc_inline += twice(it); });
    med3, max3 := measure(#code { for 1..100_000 acc_call += no_inline twice_call(it); });   // 'no_inline' at the call site
    print("median <= max for every kernel: %\n", med1 <= max1 && med2 <= max2 && med3 <= max3);
    print("inline (macro-like) and plain calls give the same result: %\n", acc_inline == acc_call);

    print("a reserved [..] does one allocation, a growing one 8: %\n", growth_allocations(true) == 1 && growth_allocations(false) == 8);
    // Print real timings to stderr only (they differ per machine and run):
    print("sum_squares median % us, inline loop % us, call loop % us\n", med1 / 1000, med2 / 1000, med3 / 1000, to_standard_error = true);
}
