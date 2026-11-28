// Module parameters STEP and LABEL; program parameter VERBOSE.
// Inside the module they are compile-time constants (usable in #if).
#module_parameters (STEP := 1, LABEL := "counter") (VERBOSE := false);

count: int;   // one global per module instance

bump :: () -> int {
    count += STEP;
    #if VERBOSE  print("[%] %\n", LABEL, count);
    return count;
}

#scope_module
#import "Basic";
