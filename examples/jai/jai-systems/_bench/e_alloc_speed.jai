// e. Allocator speed: ns per allocation and per free, for the allocators that ship with Jai and
// a tiny fixed-size slot pool written here.
//   default heap   context.default_allocator (arm64 macOS: C malloc; x64: the stripped-down
//                  rpmalloc of modules/Default_Allocator, one heap behind a spin lock)
//   temp           temporary storage, freed by reset_temporary_storage() (the build gives it a
//                  64 MiB first page, so no overflow pages are involved)
//   Flat_Pool      bump arena, freed by reset(*pool)
//   Pool           older block arena, freed by reset(*pool) (keeps its blocks)
//   rpmalloc       modules/rpmalloc with ENABLE_STATISTICS, ENABLE_ASSERTS and ENABLE_VALIDATE_ARGS
//                  set to false (its own advice for release builds); thread caches on
//   slot pool      fixed-size slots with a LIFO free list (below), called through an Allocator
//   slot pool, direct  the same pool called directly (no Allocator_Proc indirection)
// Allocations go through Basic's alloc()/free() with the allocator pushed once (push_allocator),
// as in normal code; each new block gets one 8-byte store (its index), checked before freeing.
// Patterns:
//   batch   allocate N blocks (timed), then free them in allocation order or reset (timed)
//   churn   W live blocks; each step frees a random one and allocates a replacement
//   threads T threads, each repeatedly allocating N 32-byte blocks and freeing them (or resetting
//           its own Flat_Pool); slowest thread's ns per allocate+free, vs one thread
// Arguments: "single" and/or "threads", optional thread count (default 4), "quick".
#load "harness.jai";
#import "Flat_Pool";
#import "Pool";
#import "rpmalloc"(ENABLE_STATISTICS = false, ENABLE_ASSERTS = false, ENABLE_VALIDATE_ARGS = false);
#import "Thread";
#import "Atomics";
#import "System";

Which :: enum {
    DEFAULT_HEAP;
    TEMP;
    FLAT_POOL;
    POOL;
    RPMALLOC;
    SLOT_POOL;
    SLOT_POOL_DIRECT;
}
WHICH_NAMES :: string.["default heap", "temp + reset", "Flat_Pool + reset", "Pool + reset", "rpmalloc (release flags)", "slot pool (via Allocator)", "slot pool, direct calls"];

is_bump :: (w: Which) -> bool { return w == .TEMP || w == .FLAT_POOL || w == .POOL; }
is_slot :: (w: Which) -> bool { return w == .SLOT_POOL || w == .SLOT_POOL_DIRECT; }

// ---------------------------------------------------------------- a fixed-size slot pool

Free_Slot :: struct { next: *Free_Slot; }

Slot_Pool :: struct {
    memory:    *u8;
    slot_size: s64;
    capacity:  s64;
    used:      s64;          // slots handed out from the untouched tail
    free_list: *Free_Slot;
}

slot_pool_init :: (p: *Slot_Pool, slot_size: s64, capacity: s64) {
    p.* = .{};
    p.slot_size = align_forward(max(slot_size, size_of(Free_Slot)), 16);
    p.capacity  = capacity;
    p.memory    = alloc(p.slot_size * capacity,, context.default_allocator);
}

slot_pool_fini :: (p: *Slot_Pool) { free(p.memory,, context.default_allocator); p.* = .{}; }

slot_get :: inline (p: *Slot_Pool) -> *void {
    s := p.free_list;
    if s { p.free_list = s.next; return s; }
    if p.used == p.capacity return null;
    result := p.memory + p.used * p.slot_size;
    p.used += 1;
    return result;
}

slot_put :: inline (p: *Slot_Pool, memory: *void) {
    s := cast(*Free_Slot) memory;
    s.next = p.free_list;
    p.free_list = s;
}

slot_pool_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    p := cast(*Slot_Pool) data;
    if mode == {
      case .ALLOCATE;
        if size > p.slot_size return null;
        return slot_get(p);
      case .FREE;
        if old_memory slot_put(p, old_memory);
        return null;
      case .CAPS;
        if old_memory { (cast(*string) old_memory).* = "bench slot pool"; }
        return cast(*void) Allocator_Caps.FREE;
    }
    return null;            // RESIZE and heaps: not supported
}

// ---------------------------------------------------------------- state for one size mode

Allocators :: struct {
    flat: Flat_Pool;
    pool: Pool;
    slots: Slot_Pool;
}

allocator_for :: (w: Which, state: *Allocators) -> Allocator {
    if w == {
      case .DEFAULT_HEAP; return context.default_allocator;
      case .TEMP;         return temp;
      case .FLAT_POOL;    return .{flat_pool_allocator_proc, *state.flat};
      case .POOL;         return .{pool_allocator_proc, *state.pool};
      case .RPMALLOC;     return .{rpmalloc_allocator_proc, null};
      case;               return .{slot_pool_allocator_proc, *state.slots};
    }
}

release_all :: (w: Which, state: *Allocators) {
    if w == {
      case .TEMP;      reset_temporary_storage();
      case .FLAT_POOL; reset(*state.flat);
      case .POOL;      reset(*state.pool);
    }
}

// ---------------------------------------------------------------- inner loops

alloc_n :: (sizes: [] s64, blocks: [] *void) {
    for i: 0..blocks.count-1 {
        p := alloc(sizes[i]);
        (cast(*s64) p).* = i;
        blocks[i] = p;
    }
}

free_n :: (blocks: [] *void) {
    for blocks free(it);
}

alloc_n_direct :: (pool: *Slot_Pool, blocks: [] *void) {
    for i: 0..blocks.count-1 {
        p := slot_get(pool);
        (cast(*s64) p).* = i;
        blocks[i] = p;
    }
}

free_n_direct :: (pool: *Slot_Pool, blocks: [] *void) {
    for blocks slot_put(pool, it);
}

check_blocks :: (blocks: [] *void) -> bool {
    for blocks if (cast(*s64) it).* != it_index return false;
    return true;
}

churn_steps :: (live: [] *void, victims: [] u32, sizes: [] s64) -> s64 {
    sum: s64;
    for k: 0..victims.count-1 {
        i := victims[k];
        sum += (cast(*s64) live[i]).*;
        free(live[i]);
        p := alloc(sizes[k]);
        (cast(*s64) p).* = k;
        live[i] = p;
    }
    return sum;
}

churn_steps_direct :: (pool: *Slot_Pool, live: [] *void, victims: [] u32) -> s64 {
    sum: s64;
    for k: 0..victims.count-1 {
        i := victims[k];
        sum += (cast(*s64) live[i]).*;
        slot_put(pool, live[i]);
        p := slot_get(pool);
        (cast(*s64) p).* = k;
        live[i] = p;
    }
    return sum;
}

// ---------------------------------------------------------------- batch and churn

Batch :: struct { alloc, free: Timing; ok: bool; }

run_batch :: (w: Which, state: *Allocators, sizes: [] s64, blocks: [] *void) -> Batch {
    result := Batch.{ok = true};
    a := allocator_for(w, state);
    samples_alloc, samples_free: [MAX_RUNS] s64;
    for r: -1..runs-1 {                     // r = -1: warm-up
        t0 := current_time_monotonic();
        if w == .SLOT_POOL_DIRECT alloc_n_direct(*state.slots, blocks);
        else { push_allocator(a); alloc_n(sizes, blocks); }
        t1 := current_time_monotonic();
        if !check_blocks(blocks) result.ok = false;
        t2 := current_time_monotonic();
        if is_bump(w)                 release_all(w, state);
        else if w == .SLOT_POOL_DIRECT free_n_direct(*state.slots, blocks);
        else { push_allocator(a); free_n(blocks); }
        t3 := current_time_monotonic();
        if r >= 0 {
            samples_alloc[r] = to_nanoseconds(t1 - t0);
            samples_free[r]  = to_nanoseconds(t3 - t2);
        }
    }
    result.alloc = per_op(summarize(samples_alloc, runs), blocks.count);
    result.free  = per_op(summarize(samples_free, runs), blocks.count);
    return result;
}

run_churn :: (w: Which, state: *Allocators, live: [] *void, victims: [] u32, sizes: [] s64, checksum: *s64) -> Timing {
    a := allocator_for(w, state);
    push_allocator(a);
    for * live { it.* = alloc(sizes[it_index]); (cast(*s64) it.*).* = it_index; }
    t: Timing;
    if w == .SLOT_POOL_DIRECT {
        t = measure(#code { checksum.* += churn_steps_direct(*state.slots, live, victims); });
    } else {
        t = measure(#code { checksum.* += churn_steps(live, victims, sizes); });
    }
    for live free(it);
    return per_op(t, victims.count);
}

// ---------------------------------------------------------------- threads

gate:  s32;
ready: s32;
threads_ok := true;

Thread_Job :: struct {
    which:      Which;            // DEFAULT_HEAP, RPMALLOC or FLAT_POOL
    batches:    s64;
    n:          s64;
    elapsed_ns: s64;
    ok:         bool;
}

thread_alloc_job :: (thread: *Thread) -> s64 {
    job := cast(*Thread_Job) thread.data;
    blocks := NewArray(job.n, *void,, context.default_allocator);
    sizes  := NewArray(job.n, s64,, context.default_allocator);
    for * sizes it.* = 32;
    if job.which == .RPMALLOC rpmalloc_allocator_proc(.THREAD_START, 0, 0, null, null);   // POSIX threads get no THREAD_START
    flat: Flat_Pool;
    a: Allocator;
    if job.which == {
      case .DEFAULT_HEAP; a = context.default_allocator;
      case .RPMALLOC;     a = .{rpmalloc_allocator_proc, null};
      case .FLAT_POOL;    a = .{flat_pool_allocator_proc, *flat};
    }
    job.ok = true;

    atomic_add(*ready, 1);
    while atomic_load(*gate) == 0 spin();
    t0 := current_time_monotonic();
    for 1..job.batches {
        push_allocator(a);
        alloc_n(sizes, blocks);
        if it == job.batches && !check_blocks(blocks) job.ok = false;   // last round only
        if job.which == .FLAT_POOL reset(*flat);
        else                       free_n(blocks);
    }
    job.elapsed_ns = to_nanoseconds(current_time_monotonic() - t0);

    if job.which == .RPMALLOC rpmalloc_allocator_proc(.THREAD_STOP, 0, 0, null, null);
    fini(*flat);
    array_free(blocks,, context.default_allocator);
    array_free(sizes,, context.default_allocator);
    return 0;
}

run_threads_once :: (which: Which, threads: s64, batches: s64, n: s64) -> float64 {
    thread_array: [16] Thread;
    jobs: [16] Thread_Job;
    gate, ready = 0, 0;
    for t: 0..threads-1 {
        jobs[t] = .{which = which, batches = batches, n = n};
        thread_init(*thread_array[t], thread_alloc_job);
        thread_array[t].data = *jobs[t];
        thread_start(*thread_array[t]);
    }
    while atomic_load(*ready) < threads spin();
    atomic_store(*gate, 1);
    for t: 0..threads-1 { thread_is_done(*thread_array[t], -1); thread_deinit(*thread_array[t]); }
    slowest: s64;
    for t: 0..threads-1 {
        slowest = max(slowest, jobs[t].elapsed_ns);
        if !jobs[t].ok threads_ok = false;
    }
    return cast(float64) slowest / (batches * n);
}

measure_threads :: (which: Which, threads: s64, batches: s64, n: s64) -> Timing {
    samples: [MAX_RUNS] s64;
    run_threads_once(which, threads, batches, n);
    for r: 0..runs-1 samples[r] = cast(s64) (1000 * run_threads_once(which, threads, batches, n));
    t := summarize(samples, runs);
    return .{t.median_ns / 1000, t.min_ns / 1000};
}

// ---------------------------------------------------------------- main

SIZE_MODES :: string.["32 bytes", "256 bytes", "mixed 16..512 bytes"];

main :: () {
    args := parse_common_args();
    do_single, do_threads := false, false;
    thread_count := 4;
    for args {
        if it == "single"  do_single = true;
        if it == "threads" do_threads = true;
        value, ok := string_to_int(it);
        if ok && value >= 2 && value <= 16 thread_count = value;
    }
    if !do_single && !do_threads { do_single = true; do_threads = true; }

    rpmalloc_allocator_proc(.STARTUP, 0, 0, null, null);
    random_seed(5);
    checksum: s64;
    all_ok := true;

    N      : s64 = ifx quick then 20_000 else 100_000;     // batch size
    W      : s64 = 10_000;                                 // live blocks during churn
    STEPS  : s64 = ifx quick then 200_000 else 1_000_000;  // churn steps per timed run

    _, default_name := get_capabilities(context.default_allocator);

    if do_single {
        print("### e. Allocator speed (one thread): ns per operation, median of % runs (min)\n\n", runs);
        print("Default allocator here: \"%\". Batch: % blocks allocated, then freed in the same order (bump allocators: one reset, divided by %). Churn: % live blocks, % steps of free-random + allocate.\n\n", default_name, N, N, W, STEPS);

        blocks := NewArray(N, *void);
        sizes  := NewArray(max(N, STEPS), s64);
        live   := NewArray(W, *void);
        victims := NewArray(STEPS, u32);
        for * victims it.* = cast(u32) (random_get() % cast(u64) W);

        for mode: 0..SIZE_MODES.count-1 {
            for * sizes it.* = ifx mode == 0 then 32 else ifx mode == 1 then 256 else cast(s64) (16 + random_get() % 497);
            state: Allocators;
            set_allocators(*state.pool);
            slot_size := ifx mode == 0 then 32 else 256;
            print("**%**\n\n", SIZE_MODES[mode]);
            print_table_header("allocator", .["batch: allocate", "batch: free / reset", "churn: free + allocate"]);
            for w: 0..WHICH_NAMES.count-1 {
                which := cast(Which) w;
                if is_slot(which) && mode == 2 continue;           // fixed-size only
                if is_slot(which) slot_pool_init(*state.slots, slot_size, N);
                b := run_batch(which, *state, sizes, blocks);
                if !b.ok all_ok = false;
                churn := "n/a (no reuse)";
                if !is_bump(which) churn = cell(run_churn(which, *state, live, victims, array_view(sizes, 0, STEPS), *checksum));
                freeing := cell(b.free);
                if is_bump(which) freeing = tprint("one reset: % ns in all", number(b.free.median_ns * N));
                print("| % | % | % | % |\n", WHICH_NAMES[w], cell(b.alloc), freeing, churn);
                if is_slot(which) slot_pool_fini(*state.slots);
            }
            print("\n");
            fini(*state.flat);
            release(*state.pool);
        }
    }

    if do_threads {
        batches : s64 = ifx quick then 20 else 100;
        n : s64 = 10_000;
        print("### e. Allocator speed with threads: ns per allocate+free of 32 bytes, per thread (slowest thread), median of % runs (min)\n\n", runs);
        print("Each thread: % rounds of allocating % blocks and freeing them (Flat_Pool: its own pool, reset per round).\n\n", batches, n);
        print_table_header("allocator", .["1 thread", tprint("% threads", thread_count), "slowdown"]);
        for which: Which.[.DEFAULT_HEAP, .RPMALLOC, .FLAT_POOL] {
            one  := measure_threads(which, 1, batches, n);
            many := measure_threads(which, thread_count, batches, n);
            name := ifx which == .FLAT_POOL then "Flat_Pool per thread + reset" else WHICH_NAMES[which];
            print("| % | % | % | %x |\n", name, cell(one), cell(many), formatFloat(many.median_ns / one.median_ns, trailing_width = 1, zero_removal = .NO));
        }
        print("\n");
    }
    all_ok = all_ok && threads_ok;
    if do_single print("Every block kept its contents until freed: %. Checksum %.\n\n", all_ok, checksum);
    else         print("Every block kept its contents until freed: %.\n\n", all_ok);
}
