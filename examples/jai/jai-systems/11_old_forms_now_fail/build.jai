// Old Jai you will meet in blog posts, old tutorials and third-party code, and what 0.2.032 says.
// The compiler stops at the first error of a workspace, so this metaprogram compiles every old_*.jai
// file in its own workspace: one run reports all of them. Each file names the current form.
//
//   old code                                   current form                                  changed in
//   c: Context;                                c: #Context;  (or Context_Base for allocator/  0.2.002 (removed)
//                                              logger parameters)
//   alloc(n, a), New(T, allocator = a),        alloc(n,, a), New(T,, a), copy_string(s,, a)   0.1.080 (,, call syntax)
//   copy_string(s, a), free(p, a)              free(p,, a)
//   __temporary_allocator                      temp  (or temporary_allocator)                0.2.029 (removed)
//   New(T, initialized = false)                New(T, initialize = false)                     0.2.032 (no deprecation)
//   get_time()                                 seconds_since_init(), current_time_monotonic() 0.2.002 (removed)
//   get_system_time(), System_Time             current_time_consensus() + to_calendar()       0.2.002 (removed)
//   get_stack_trace_string(node)               get_stack_trace_strings(node) (temp array)     0.2.020
//   Push_Temporary()                           auto_release_temp() / marks                    0.1.028 (removed)
//   thread_create / thread_uninit              thread_init / thread_deinit (Thread you own)   0.1.071 (removed)
//   lock_cmpxchg(...)                          ok, old := compare_and_swap(*x, old, new)      0.2.009 (removed)
//   TEMP_ALLOCATOR_POISON_FREED_MEMORY=true    TEMP_ALLOCATOR_OVERWRITE_MEMORY=true           0.2.028
//   context.allocator = my_allocator_proc      context.allocator = .{my_allocator_proc, data} 0.0.096
// Command line: -release / -release_debug only WARN (use -o / -od); -debug is "Unknown argument" (now -debugger).
//
// EXPECT-COMPILE-ERROR: old_context.jai:5,23: Error: Undeclared identifier 'Context'.
// EXPECT-COMPILE-ERROR: old_alloc_argument.jai:4,10: Error: Too many arguments: Wanted 1, got 2.
// EXPECT-COMPILE-ERROR: old_new_allocator_argument.jai:4,19: Error: Argument name 'allocator' (number 2) is not found in the procedure being called.
// EXPECT-COMPILE-ERROR: old_free_allocator_argument.jai:5,5: Error: Procedure call did not match any of the possible overloads.
// EXPECT-COMPILE-ERROR: Error: Undeclared identifier '__temporary_allocator'.
// EXPECT-COMPILE-ERROR: Error: Argument name 'initialized' (number 2) is not found in the procedure being called.
// EXPECT-COMPILE-ERROR: Error: Undeclared identifier 'get_time'.
// EXPECT-COMPILE-ERROR: Error: Undeclared identifier 'get_system_time'.
// EXPECT-COMPILE-ERROR: Error: Undeclared identifier 'get_stack_trace_string'.
// EXPECT-COMPILE-ERROR: Error: Undeclared identifier 'Push_Temporary'.
// EXPECT-COMPILE-ERROR: Error: Undeclared identifier 'thread_create'.
// EXPECT-COMPILE-ERROR: Error: Undeclared identifier 'lock_cmpxchg'.
// EXPECT-COMPILE-ERROR: Error: Argument name 'TEMP_ALLOCATOR_POISON_FREED_MEMORY' (number 1) is not found in the program parameters.
// EXPECT-COMPILE-ERROR: Error: Type mismatch. Type wanted: Allocator; type given: (Allocator_Mode, s64, s64, *void, *void) -> (*void).
#import "Basic";
#import "Compiler";
#import "File_Utilities";

#run {
    set_build_options_dc(.{do_output = false});
    for file_list(#filepath) {
        _, name := path_decomp(it);
        if !begins_with(name, "old_") continue;
        w := compiler_create_workspace(name);
        options := get_build_options(w);
        options.output_type = .NO_OUTPUT;          // only the diagnostics matter
        options.text_output_flags = 0;
        set_build_options(options, w);
        add_build_file(it, w);
    }
}

#import "String";
