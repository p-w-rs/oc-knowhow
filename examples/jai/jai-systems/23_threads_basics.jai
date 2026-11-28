// modules/Thread: a Thread struct you own, a proc (*Thread) -> s64, and four calls:
//   thread_init(*t, proc, temporary_storage_size = 16384, name = "") -> bool
//   thread_start(*t)            the thread is created suspended; this lets it run
//   thread_is_done(*t, ms)      poll (0), wait up to ms, or -1 = wait until it finishes
//   thread_deinit(*t)           joins (POSIX) and frees its temporary storage
// t.data is a free *void for your input/output. Each thread gets its own context copy
// (thread_index 1, 2, ...) and its own temporary storage.
// Mutex (init/lock/unlock/destroy) is recursive on POSIX platforms.
// EXPECT: 4 workers summed 1..1000000 in parallel: 500000500000
// EXPECT: per-thread results: 31250125000 93750125000 156250125000 218750125000
// EXPECT: workers ran on thread indices 1..4: true
// EXPECT: shared counter under a mutex: 4000
#import "Basic";
#import "Thread";

Job :: struct {
    first, last: int;
    sum: int;
    thread_index: u32;
}

counter: int;
counter_mutex: Mutex;

sum_job :: (thread: *Thread) -> s64 {
    job := cast(*Job) thread.data;
    for job.first..job.last job.sum += it;
    job.thread_index = context.thread_index;
    for 1..1000 {
        lock(*counter_mutex);
        counter += 1;
        unlock(*counter_mutex);
    }
    return 0;
}

main :: () {
    init(*counter_mutex);
    defer destroy(*counter_mutex);

    N :: 1_000_000;
    jobs: [4] Job;
    threads: [4] Thread;
    for * threads {
        jobs[it_index].first = it_index * (N / 4) + 1;
        jobs[it_index].last  = (it_index + 1) * (N / 4);
        ok := thread_init(it, sum_job, name = tprint("summer %", it_index));
        assert(ok, "thread_init failed");
        it.data = *jobs[it_index];
    }
    for * threads thread_start(it);
    for * threads {
        thread_is_done(it, -1);           // wait for completion
        thread_deinit(it);
    }

    total := 0;
    indices_ok := true;
    for jobs {
        total += it.sum;
        if it.thread_index < 1 || it.thread_index > 4 indices_ok = false;
    }
    print("4 workers summed 1..1000000 in parallel: %\n", total);
    print("per-thread results: % % % %\n", jobs[0].sum, jobs[1].sum, jobs[2].sum, jobs[3].sum);
    print("workers ran on thread indices 1..4: %\n", indices_ok);
    print("shared counter under a mutex: %\n", counter);
}
