// What a new thread's context contains (modules/Thread, 0.2.032): thread_init copies ONLY
// allocator, logger, logger_data and assertion_failed from the creating thread, gives the thread
// its own temporary storage and a new thread_index. Everything else starts from #Context's
// initializers: your #add_context fields do NOT follow you into the thread.
// Fix: assign the global hook thread_init_handler (called at the end of every thread_init,
// including Thread_Group workers) and copy the fields into t.starting_context.
// EXPECT: main: log_prefix="[server] " request_limit=8
// EXPECT: plain thread: log_prefix="" request_limit=1 (allocator inherited: true)
// EXPECT: with thread_init_handler: log_prefix="[server] " request_limit=8
#import "Basic";
#import "Thread";

#add_context log_prefix := "";
#add_context request_limit := 1;

report :: (thread: *Thread) -> s64 {
    label := cast(*string) thread.data;
    print("%: log_prefix=\"%\" request_limit=%", label.*, context.log_prefix, context.request_limit);
    if label.* == "plain thread" print(" (allocator inherited: %)", context.allocator.proc == counting_proc);
    print("\n");
    return 0;
}

counting_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old: *void, data: *void) -> *void {
    return context.default_allocator.proc(mode, size, old_size, old, data);
}

run_one :: (label: string) {
    t: Thread;
    l := label;
    thread_init(*t, report);
    t.data = *l;
    thread_start(*t);
    thread_is_done(*t, -1);
    thread_deinit(*t);
}

main :: () {
    context.log_prefix = "[server] ";
    context.request_limit = 8;
    context.allocator = .{counting_proc, null};
    print("main: log_prefix=\"%\" request_limit=%\n", context.log_prefix, context.request_limit);

    run_one("plain thread");

    thread_init_handler = (t: *Thread) {
        // Runs on the creating thread, so 'context' here is the creator's context.
        t.starting_context.log_prefix    = context.log_prefix;
        t.starting_context.request_limit = context.request_limit;
    };
    run_one("with thread_init_handler");
}
