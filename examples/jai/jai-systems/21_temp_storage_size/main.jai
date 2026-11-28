#import "Basic";
#import "Thread";

worker :: (thread: *Thread) -> s64 {
    print("worker thread temporary storage: % bytes\n", context.temporary_storage.size);
    return 0;
}

main :: () {
    print("main thread temporary storage: % bytes\n", context.temporary_storage.size);
    for 1..200 talloc(1024);
    ts := cast(*Temporary_Storage_Paged_Alloc) context.temporary_storage;
    print("200 KiB of temp allocations, overflow pages: %\n", ifx ts.overflow_pages then 1 else 0);
    reset_temporary_storage();

    t: Thread;
    thread_init(*t, worker, temporary_storage_size = 256 * 1024);
    thread_start(*t);
    while !thread_is_done(*t, -1) {}
    thread_deinit(*t);
}
