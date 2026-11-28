// Which build am I? A constant initialized by #run get_build_options() inside the program sees
// the options of the program's OWN workspace, so code can report or branch on its build mode.
// Built here with -o (JAI-ARGS below): Default_Metaprogram calls set_optimization(.VERY_OPTIMIZED)
// (bounds/cast/null checks OFF, LLVM O3 + loop/SLP vectorization) and sets stack_trace = false.
//   jai f.jai            debug: checks ON, stack traces ON, LLVM -O0 (UNSET)
//   jai f.jai -od        OPTIMIZED (O2), checks OFF, stack traces kept
//   jai f.jai -o         VERY_OPTIMIZED (O3), checks OFF, stack traces OFF
//   jai f.jai -very_debug  VERY_DEBUG (same checks as debug in 0.2.032; overflow checks still OFF)
// JAI-ARGS: -o
// EXPECT: backend=LLVM optimization=O3 stack_trace=false
// EXPECT: checks: array_bounds=OFF cast_bounds=OFF null_pointer=OFF arithmetic_overflow=OFF
// EXPECT: context.stack_trace has no procedure info in this build: true
#import "Basic";
#import "Compiler";

BUILD :: #run get_build_options();

main :: () {
    print("backend=% optimization=% stack_trace=%\n", BUILD.backend, BUILD.llvm_options.bitcode_optimization_setting, BUILD.stack_trace);
    print("checks: array_bounds=% cast_bounds=% null_pointer=% arithmetic_overflow=%\n",
        BUILD.array_bounds_check, BUILD.cast_bounds_check, BUILD.null_pointer_check, BUILD.arithmetic_overflow_check);
    // With stack traces off, context.stack_trace still points at a sentinel node (never null).
    node := context.stack_trace;
    print("context.stack_trace has no procedure info in this build: %\n", node == null || node.info == null);
}
