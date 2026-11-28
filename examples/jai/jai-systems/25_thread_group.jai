// Thread_Group (modules/Thread/thread_group.jai): N worker threads all running ONE procedure,
// each with its own input and output queue (work is assigned round-robin; optional work stealing).
//   init(*group, num_threads, proc, enable_work_stealing = false, temporary_storage_size = 16384, group_name = "")
//   group.logging = false     // it is TRUE by default and logs every add/assign/complete!
//   start(*group); add_work(*group, *work); get_completed_work(*group) -> [] *void (in temp storage)
//   shutdown(*group)          // waits for the workers, then frees them
// The proc signature is (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status.
// Work items are YOUR memory: keep them alive until they come back from get_completed_work.
// EXPECT: 64 chunks done, total 2048032000, matches formula: true
// EXPECT: every chunk was processed by a worker thread: true
#import "Basic";
#import "Thread";
#import "System";

Chunk :: struct {
    first, last: int;
    sum: int;
    worker_thread_index: u32;
}

sum_chunk :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    c := cast(*Chunk) work;
    for c.first..c.last c.sum += it;
    c.worker_thread_index = context.thread_index;
    reset_temporary_storage();          // each worker owns its temp storage; reset per work item
    return .CONTINUE;
}

main :: () {
    workers := clamp(get_number_of_processors() - 1, 1, 8);
    group: Thread_Group;
    init(*group, cast(s32) workers, sum_chunk, enable_work_stealing = true);
    group.logging = false;
    start(*group);

    chunks: [64] Chunk;
    N :: 64_000;
    for * chunks {
        it.first = it_index * (N / chunks.count) + 1;
        it.last  = (it_index + 1) * (N / chunks.count);
        add_work(*group, it);
    }

    done, total := 0, 0;
    while done < chunks.count {
        for get_completed_work(*group) {
            total += (cast(*Chunk) it).sum;
            done += 1;
        }
        reset_temporary_storage();       // the completed-work array lives in temp storage
        if done < chunks.count sleep_milliseconds(1);
    }
    shutdown(*group);

    on_workers := true;
    for chunks if it.worker_thread_index == 0 on_workers = false;
    print("% chunks done, total %, matches formula: %\n", done, total, total == N * (N + 1) / 2);
    print("every chunk was processed by a worker thread: %\n", on_workers);
}
