// Inside a #c_call (or #no_context) procedure there is no context, so it cannot
// call ordinary Jai procedures such as print. Wrap that part in push_context { },
// which creates a default context for the block (see 29_c_static_library).
// EXPECT-COMPILE-ERROR: Cannot call into a native procedure, from a #c_call procedure, without using push_context

#import "Basic";

on_event :: (code: s32) -> s32 #c_call {
    print("event %\n", code);          // needs: push_context { print(...); }
    return code;
}

main :: () { on_event(1); }
