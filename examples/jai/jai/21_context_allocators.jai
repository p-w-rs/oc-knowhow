// EXPECT: depth 0
// EXPECT:     depth 2 (inside push_context)
// EXPECT: depth 0 (restored)
// EXPECT:   depth 1 (plain assignment sticks for this scope)
// EXPECT: counted allocations: 2 (only the ,, calls)
// EXPECT: temp string 'temp 42', temporary storage in use: true
// EXPECT: after reset_temporary_storage: 0 bytes
// EXPECT: push_allocator until scope end: 3
// `context` is an implicit struct passed to every (non-#c_call) procedure: allocator, logger,
// temporary_storage, stack_trace, thread_index, print_style, plus anything added with #add_context.
//   push_context c { ... }   use context c for the block (callees see it), then restore
//   f(args,, allocator = a)  override context fields for one call (",," then field = value)
//   f(args,, a)              shorthand for allocator = a
//   push_allocator(a)        Basic macro: context.allocator = a until the end of the enclosing scope
// Allocators are { proc, data }; the proc signature is Allocator_Proc in modules/Preload.jai.
// Memory strategy in depth (arenas, Pool, Flat_Pool, temp marks) is the jai-systems skill.

#import "Basic";

#add_context depth: int;       // your own context field (one per thread, no TLS cost)

report :: (note := "") {
    for 1..context.depth  print("  ");
    print("depth %%\n", context.depth, note);
}

counting_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    if mode == .ALLOCATE then (cast(*int) data).* += 1;   // `then` needed: a '(' right after the condition would parse as a call
    return context.default_allocator.proc(mode, size, old_size, old_memory, null);   // forward to the heap
}

make_name :: (i: int) -> string { return sprint("name_%", i); }   // allocates from context.allocator

main :: () {
    report();
    {
        c := context;
        c.depth = 2;
        push_context c { report(" (inside push_context)"); }
    }
    report(" (restored)");
    {
        context.depth = 1;
        report(" (plain assignment sticks for this scope)");
        context.depth = 0;
    }

    count := 0;
    counter := Allocator.{counting_proc, *count};
    a := make_name(1);                         // default heap allocator
    b := make_name(2,, counter);
    c := make_name(3,, allocator = counter);
    print("counted allocations: % (only the ,, calls)\n", count);

    t := tprint("temp %", 42);                 // temporary storage: no free needed
    print("temp string '%', temporary storage in use: %\n", t, context.temporary_storage.total_bytes_occupied > 0);
    reset_temporary_storage();                 // e.g. once per frame / per request
    print("after reset_temporary_storage: % bytes\n", context.temporary_storage.total_bytes_occupied);

    {
        push_allocator(counter);
        d := copy_string("abc");
        print("push_allocator until scope end: %\n", count);
    }
}
