// False sharing, as layout: which cache line does each thread's counter land on?
// Caches keep coherence per LINE: before a core writes, it takes the whole line exclusively and the
// other cores' copies are invalidated. Two threads writing different variables in the same line
// therefore take turns owning it ("false sharing"), which can make each write many times slower.
// The fix is layout: give each thread's hot data its own line(s).
// - Line size: 64 bytes on the Intel machines, 128 bytes on Apple M-series (hw.cachelinesize).
//   Padding to 64 leaves PAIRS of counters in one 128-byte line; padding to 128 is safe on both
//   (the measured cost of each layout is in reference/caches.md and _bench/c_false_sharing.jai).
// - `value: s64 #align 128;` as a member makes the struct 128 bytes and 128-aligned; `#align` also
//   works on globals and locals. The heap does not honor it: New and NewArray only get the
//   allocator's alignment (16 bytes is all you can count on); use NewArray(n, T, alignment = 128) and
//   free the returned unaligned_base.
// - Thread_Group pads its per-worker records with the Thread module's CACHE_LINE_SIZE (default 64).
//   It is a program parameter: #import "Thread"()(CACHE_LINE_SIZE=128); (the first parameter list,
//   (CACHE_LINE_SIZE=128), is rejected). Read it back through a named import of the module.
// - type_info(T).alignment is unreliable in 0.2.032 (it reads -1 once T appears in a procedure
//   signature or a global declaration, see example 49): align_of below uses a probe struct instead.
// - Only the address matters, not the type: each thread owning its slot is correct with any padding;
//   padding changes speed only. Even better: count in a local and store once at the end.
// EXPECT: counter 0..7 line index with 64 B lines:  adjacent 0 0 0 0 0 0 0 0 | pad 64: 0 1 2 3 4 5 6 7 | pad 128: 0 2 4 6 8 10 12 14
// EXPECT: counter 0..7 line index with 128 B lines: adjacent 0 0 0 0 0 0 0 0 | pad 64: 0 0 1 1 2 2 3 3 | pad 128: 0 1 2 3 4 5 6 7
// EXPECT: Padded_64: size 64, alignment 64; Padded_128: size 128, alignment 128
// EXPECT: global and local #align 128 arrays start on a 128-byte boundary: true true
// EXPECT: NewArray(8, Padded_128, alignment = 128) starts on a 128-byte boundary: true
// EXPECT: Thread module CACHE_LINE_SIZE = 128; Worker_Info's padding ends on a multiple of it: true
// EXPECT: this machine reports a 64- or 128-byte line: true
// EXPECT: 4 threads, own padded slots, incremented in place: 4000000 (expected 4000000)
// EXPECT: 4 threads, local count, one store each at the end: 4000000 (expected 4000000)
// EXPECT-CONTAINS: reported cache line size:
#import "Basic";
#import "POSIX";
#import "Thread"()(CACHE_LINE_SIZE=128);
Thread_Module :: #import "Thread";      // the same module instance, named, to read its parameter

Padded_64  :: struct { value: s64 #align 64;  }
Padded_128 :: struct { value: s64 #align 128; }

Align_Probe :: struct (T: Type) { first: u8; value: T; }   // value lands on T's alignment
align_of :: ($T: Type) -> s64 { return type_info(Align_Probe(T)).members[1].offset_in_bytes; }

global_slots: [8] Padded_128;           // #align inside the type: the global is 128-aligned

line_indices :: (addresses: [] u64, line: u64) -> string {
    builder: String_Builder;
    first := addresses[0] / line;
    for addresses {
        if it_index print(*builder, " ");
        print(*builder, "%", it / line - first);
    }
    return builder_to_string(*builder,, temp);
}

reported_line_size :: () -> int {
    #if OS == .MACOS {
        value: s64;
        size: u64 = size_of(s64);
        if sysctlbyname(temp_c_string("hw.cachelinesize"), *value, *size, null, 0) != 0 return 0;
        return value;
    } else {
        return sysconf(._SC_LEVEL1_DCACHE_LINESIZE);
    }
}

INCREMENTS :: 1_000_000;
THREADS    :: 4;

Job :: struct {
    slot:    *s64;              // this thread's counter, in a padded array
    in_place: bool;
}

count_job :: (thread: *Thread) -> s64 {
    job := cast(*Job) thread.data;
    if job.in_place {
        // A real store per increment (atomic_store keeps the compiler from moving it out of the
        // loop); no other thread writes this slot, so it needs no atomic read-modify-write.
        for 1..INCREMENTS atomic_store(job.slot, atomic_load(job.slot) + 1);
    } else {
        local := 0;
        for 1..INCREMENTS local += 1;
        job.slot.* = local;     // one store: the line is touched once
    }
    return 0;
}

run_threads :: (slots: [] Padded_128, in_place: bool) -> s64 {
    threads: [THREADS] Thread;
    jobs: [THREADS] Job;
    for * threads {
        jobs[it_index] = .{slot = *slots[it_index].value, in_place = in_place};
        thread_init(it, count_job);
        it.data = *jobs[it_index];
    }
    for * threads thread_start(it);
    for * threads { thread_is_done(it, -1); thread_deinit(it); }
    total: s64;
    for slots total += it.value;
    return total;
}

main :: () {
    adjacent: [8] s64 #align 128;
    pad64:    [8] Padded_64 #align 128;
    pad128:   [8] Padded_128;
    a, p64, p128: [8] u64;
    for 0..7 {
        a[it]    = cast(u64) *adjacent[it];
        p64[it]  = cast(u64) *pad64[it].value;
        p128[it] = cast(u64) *pad128[it].value;
    }
    for line: u64.[64, 128] {
        print("counter 0..7 line index with % B lines:%adjacent % | pad 64: % | pad 128: %\n", line, ifx line == 64 then "  " else " ",
            line_indices(a, line), line_indices(p64, line), line_indices(p128, line));
    }
    print("Padded_64: size %, alignment %; Padded_128: size %, alignment %\n",
        size_of(Padded_64), align_of(Padded_64), size_of(Padded_128), align_of(Padded_128));
    print("global and local #align 128 arrays start on a 128-byte boundary: % %\n",
        (cast(u64) global_slots.data) % 128 == 0, (cast(u64) adjacent.data) % 128 == 0);

    heap_slots, unaligned_base := NewArray(8, Padded_128, alignment = 128);
    print("NewArray(8, Padded_128, alignment = 128) starts on a 128-byte boundary: %\n", (cast(u64) heap_slots.data) % 128 == 0);
    plain_slots := NewArray(8, Padded_128);   // no alignment argument: only the allocator's alignment
    plain_offset := (cast(u64) plain_slots.data) % 128;

    padding_end := -1;
    for type_info(Thread_Group.Worker_Info).members if it.name == "work_steal_indices" padding_end = it.offset_in_bytes;
    print("Thread module CACHE_LINE_SIZE = %; Worker_Info's padding ends on a multiple of it: %\n",
        Thread_Module.CACHE_LINE_SIZE, padding_end > 0 && padding_end % Thread_Module.CACHE_LINE_SIZE == 0);

    line := reported_line_size();
    print("this machine reports a 64- or 128-byte line: %\n", line == 64 || line == 128);

    slots := heap_slots;
    print("% threads, own padded slots, incremented in place: % (expected %)\n", THREADS, run_threads(slots, true), THREADS * INCREMENTS);
    for * slots it.value = 0;
    print("% threads, local count, one store each at the end: % (expected %)\n", THREADS, run_threads(slots, false), THREADS * INCREMENTS);
    free(unaligned_base);

    print("reported cache line size: % bytes; NewArray without alignment started % bytes past a 128-byte boundary\n",
        line, plain_offset, to_standard_error = true);
}
