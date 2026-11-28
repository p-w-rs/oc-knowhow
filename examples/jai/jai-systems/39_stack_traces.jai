// Jai's own stack traces: with Build_Options.stack_trace = true (default; -o turns it off) every
// call pushes a Stack_Trace_Node on the stack and links it from context.stack_trace. Walking it is
// cheap and identical on every platform; node.info has the procedure name and declaration location.
// node.line_number is the line of the call this frame is CURRENTLY making: for an outer frame
// that is where it called the next one in; for the innermost frame it is the line of the latest
// call made from it (line 22 while printing, 23 once it calls pack_stack_trace).
// The chain ends in a sentinel node with info == null (skip it, like print_stack_trace does).
// - print_stack_trace(node)          low-level, never allocates or logs (stderr by default)
// - get_stack_trace_strings()        [..] string in temporary storage
// - pack_stack_trace(node)           a heap copy you can keep after the frames are gone
//   (the no-argument pack_stack_trace() also records its own frames)
// Cost: about 2-3x on call-heavy code like naive fib in debug builds (reference/performance.md).
// EXPECT: innermost frame's current call is on line 22
// EXPECT: level_c:23 <- level_b:25 <- level_a:26 <- main:29
// EXPECT: packed copy: 5 nodes (4 procedures + sentinel), first = level_c
#import "Basic";

saved: [] Stack_Trace_Node;

level_c :: () {
    node := context.stack_trace;
    print("innermost frame's current call is on line %\n", node.line_number);
    saved = pack_stack_trace(context.stack_trace);   // heap copy, valid after we return
}
level_b :: () { level_c(); }
level_a :: () { level_b(); }

main :: () {
    level_a();
    // The packed copy outlives the frames; its 'next' pointers point into the array.
    builder: String_Builder;
    node := saved.data;
    while node {
        if node.info {
            if node != saved.data print(*builder, " <- ");
            print(*builder, "%:%", node.info.name, node.line_number);
        }
        node = node.next;
    }
    print("%\n", builder_to_string(*builder,, temp));
    print("packed copy: % nodes (4 procedures + sentinel), first = %\n", saved.count, saved[0].info.name);
    free(saved.data);
}
