// Calling a normal Jai procedure (print needs the context) from a #c_call procedure without
// push_context is a compile error, not a runtime crash. Fix: wrap the body in push_context { }.
// EXPECT-COMPILE-ERROR: Cannot call into a native procedure, from a #c_call procedure, without using push_context
#import "Basic";

callback :: (x: s32) -> s32 #c_call {
    print("x = %\n", x);
    return x;
}

main :: () {
    callback(1);
}
