// c. False sharing and contention: T threads each add 1 to "their" counter many times.
// Reports ns per increment as seen by one thread (its loop time / its increments; the slowest
// thread of the run counts), median of the timed runs (min in parentheses), and the slowdown
// against the private-counter baseline.
//
// Counter layouts (every array is 128-byte aligned; checked at run time):
//   own line (pad 128)   each counter alone in a 128-byte slot: no sharing on any machine
//   pad 64               64-byte slots: two counters per 128-byte block
//   adjacent             s64[T]: all counters in one or two lines
//   local, publish once  each thread counts in a local variable and stores once at the end
//   one shared atomic    every thread atomic_adds the SAME counter (true sharing / contention)
// Operations on a thread's own counter:
//   plain    load, add, store (no atomics: correct because nobody else writes that counter)
//   atomic   atomic_add (x64: lock xadd; arm64 in 0.2.032: a load-exclusive/store-exclusive loop)
//
// Run with the thread counts as arguments: c_false_sharing 2 4 8   (default: 2 4)
// Each thread runs on its own OS thread; pin the process to cores of one kind (run.sh does).
#load "harness.jai";
#import "Thread";
#import "Atomics";
#import "System";

MAX_THREADS :: 16;
SLOT_BYTES  :: 128;                 // room for one counter per 128-byte slot

Layout :: enum {
    OWN_LINE_128;
    PAD_64;
    ADJACENT;
    LOCAL_PUBLISH;
    SHARED_ATOMIC;
}
LAYOUT_NAMES :: string.["own line (pad 128)", "pad 64", "adjacent (8 bytes apart)", "local, publish once", "one shared atomic"];

Operation :: enum { PLAIN; ATOMIC; }

Job :: struct {
    counter:     *s64;
    iterations:  s64;
    layout:      Layout;
    operation:   Operation;
    mask:        s64;               // always 0; read at run time so the compiler keeps every store
    elapsed_ns:  s64;
}

// Spin barrier: all workers wait until the main thread opens the gate, so they start together.
gate: s32;
ready: s32;

increment_job :: (thread: *Thread) -> s64 {
    job := cast(*Job) thread.data;
    atomic_add(*ready, 1);
    while atomic_load(*gate) == 0 spin();

    t0 := current_time_monotonic();
    n := job.iterations;
    if job.layout == {
      case .LOCAL_PUBLISH;
        local: s64;
        mask := job.mask;
        for i: 1..n { local += 1 + (i & mask); }
        job.counter.* += local;
      case .SHARED_ATOMIC;
        for 1..n atomic_add(job.counter, 1);
      case;
        if job.operation == .ATOMIC {
            for 1..n atomic_add(job.counter, 1);
        } else {
            // counter[i & mask] with mask == 0: one real load and store per increment.
            counter, mask := job.counter, job.mask;
            for i: 1..n { (counter + (i & mask)).* += 1; }
        }
    }
    job.elapsed_ns = to_nanoseconds(current_time_monotonic() - t0);
    return 0;
}

// One run: start T threads on the given layout, return the slowest thread's ns per increment.
run_once :: (threads: s64, layout: Layout, operation: Operation, iterations: s64, slots: *u8, mask: s64) -> float64 {
    thread_array: [MAX_THREADS] Thread;
    jobs: [MAX_THREADS] Job;
    for t: 0..threads-1 {
        counter: *s64;
        if layout == {
          case .OWN_LINE_128;  counter = cast(*s64) (slots + t * 128);
          case .PAD_64;        counter = cast(*s64) (slots + t * 64);
          case .ADJACENT;      counter = cast(*s64) (slots + t * 8);
          case .LOCAL_PUBLISH; counter = cast(*s64) (slots + t * 8);
          case .SHARED_ATOMIC; counter = cast(*s64) slots;
        }
        jobs[t] = .{counter = counter, iterations = iterations, layout = layout, operation = operation, mask = mask};
    }
    memset(slots, 0, MAX_THREADS * SLOT_BYTES);
    gate, ready = 0, 0;
    for t: 0..threads-1 {
        thread_init(*thread_array[t], increment_job);
        thread_array[t].data = *jobs[t];
        thread_start(*thread_array[t]);
    }
    while atomic_load(*ready) < threads spin();
    atomic_store(*gate, 1);
    for t: 0..threads-1 { thread_is_done(*thread_array[t], -1); thread_deinit(*thread_array[t]); }

    slowest: s64;
    for t: 0..threads-1 slowest = max(slowest, jobs[t].elapsed_ns);

    // Check the counts: every increment must have landed.
    total: s64;
    if layout == .SHARED_ATOMIC total = (cast(*s64) slots).*;
    else for t: 0..threads-1 total += jobs[t].counter.*;
    if total != threads * iterations {
        print("WRONG COUNT: % threads, layout %, op %: got %, expected %\n", threads, layout, operation, total, threads * iterations);
        counts_ok = false;
    }
    return cast(float64) slowest / iterations;
}

counts_ok := true;

measure_layout :: (threads: s64, layout: Layout, operation: Operation, iterations: s64, slots: *u8, mask: s64) -> Timing {
    samples: [MAX_RUNS] s64;
    run_once(threads, layout, operation, iterations, slots, mask);            // warm-up
    for r: 0..runs-1 samples[r] = cast(s64) (1000 * run_once(threads, layout, operation, iterations, slots, mask));   // picoseconds
    t := summarize(samples, runs);
    return .{t.median_ns / 1000, t.min_ns / 1000};
}

main :: () {
    args := parse_common_args();
    thread_counts: [..] s64;
    for args {
        value, ok := string_to_int(it);
        if ok && value >= 1 && value <= MAX_THREADS array_add(*thread_counts, value);
    }
    if !thread_counts array_add(*thread_counts, 2, 4);

    slots_memory, unaligned := NewArray(MAX_THREADS * SLOT_BYTES, u8, alignment = 128);
    slots := slots_memory.data;
    assert((cast(u64) slots) % 128 == 0, "counter block must be 128-byte aligned");
    mask := get_command_line_arguments().count * 0;     // 0, but unknown to the compiler

    iterations : s64 = ifx quick then 2_000_000 else 20_000_000;

    print("### c. False sharing and contention: ns per increment per thread, median of % runs (min); slowdown vs own line\n\n", runs);
    print("Each thread does % increments; the slowest thread's loop time counts. Counter block 128-byte aligned: %.\n\n", iterations, (cast(u64) slots) % 128 == 0);

    for operation: Operation.[.PLAIN, .ATOMIC] {
        print("**% increments of a thread's own counter**\n\n", ifx operation == .PLAIN then "plain (load, add, store)" else "atomic_add");
        columns: [..] string;
        array_add(*columns, "1 thread");
        for thread_counts array_add(*columns, tprint("% threads", it));
        print_table_header("layout", columns);
        own: [MAX_THREADS + 1] Timing;        // the own-line baseline per thread count
        for layout: Layout.[.OWN_LINE_128, .PAD_64, .ADJACENT, .LOCAL_PUBLISH, .SHARED_ATOMIC] {
            if operation == .ATOMIC && layout == .LOCAL_PUBLISH continue;
            if operation == .PLAIN  && layout == .SHARED_ATOMIC continue;
            print("| % |", LAYOUT_NAMES[layout]);
            print(" % |", cell(measure_layout(1, layout, operation, iterations, slots, mask)));
            for threads: thread_counts {
                t := measure_layout(threads, layout, operation, iterations, slots, mask);
                if layout == .OWN_LINE_128 own[threads] = t;
                print(" % = %x |", cell(t), formatFloat(t.median_ns / own[threads].median_ns, trailing_width = 1, zero_removal = .NO));
            }
            print("\n");
        }
        print("\n");
    }
    print("All counts correct: %.\n\n", counts_ok);
    free(unaligned);
}
