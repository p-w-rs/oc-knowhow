// Program parameters of Basic: ENABLE_ASSERT=false turns assert() into an empty
// macro for the whole program (every module's import of Basic sees it).
// Program parameters can only be given from the main program, once per module.
// Other Basic program parameters (0.2.032): MEMORY_DEBUGGER, VISUALIZE_MEMORY_DEBUGGER,
// TEMP_ALLOCATOR_OVERWRITE_MEMORY, MEMORY_DEBUGGER_REPORT_ASSERTS, REPLACEMENT_INTERFACE.
// EXPECT: before the assert
// EXPECT: after the assert: asserts are compiled out

#import "Basic"()(ENABLE_ASSERT = false);

main :: () {
    print("before the assert\n");
    assert(1 + 1 == 3, "this would stop the program if asserts were enabled");
    print("after the assert: asserts are compiled out\n");
}
