// The implicit context: one struct, passed to every non-#c_call procedure.
// #Context is the full type (Context_Base plus every #add_context field);
// Context_Base is the fixed part from Runtime_Support.jai. Basic adds print_style.
// The whole #Context is padded to Build_Options.context_size_max (4096 bytes by default).
// EXPECT: size_of(Context_Base) = 96
// EXPECT: size_of(#Context) = 4096
// EXPECT: #Context members: base print_style
// EXPECT: main runs on thread_index 0
// EXPECT: temporary storage present: true, first page 32768 bytes
// EXPECT: allocator is the default allocator: true
// EXPECT: stack trace present: true, innermost procedure: main
// EXPECT: log_level: NORMAL
#import "Basic";

main :: () {
    print("size_of(Context_Base) = %\n", size_of(Context_Base));
    print("size_of(#Context) = %\n", size_of(#Context));

    // Reflection works on the context type like on any struct.
    print("#Context members:");
    for type_info(#Context).members print(" %", it.name);
    print("\n");

    print("main runs on thread_index %\n", context.thread_index);
    ts := context.temporary_storage;
    print("temporary storage present: %, first page % bytes\n", ts != null, ts.size);
    print("allocator is the default allocator: %\n", context.allocator.proc == context.default_allocator.proc);

    // With stack traces on (the default; -o turns them off) every call links a node.
    node := context.stack_trace;
    print("stack trace present: %, innermost procedure: %\n", node != null, node.info.name);
    print("log_level: %\n", context.log_level);
}
