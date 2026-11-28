// Replaced in 0.2.020 by get_stack_trace_strings(node): one temp string per frame.
#import "Basic";
main :: () { s := get_stack_trace_string(context.stack_trace); }
