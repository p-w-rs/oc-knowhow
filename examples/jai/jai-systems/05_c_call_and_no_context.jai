// #c_call procedures use the C ABI and receive no context; #no_context procedures use the Jai
// ABI but also skip the hidden context parameter. Neither may call context-using procedures
// directly. Inside them, push_context {} creates a DEFAULT context (allocator = default heap,
// thread_index = 0xFFFF_FFFF, no temporary storage, #add_context fields at their initializers),
// or push a context you saved earlier, e.g. through the user-data pointer that C callbacks get.
// EXPECT: default context in callback: thread_index=4294967295 temp=false tag=0
// EXPECT: saved context in callback: thread_index=0 temp=true tag=42
// EXPECT: callback results 6 20
// EXPECT: #no_context add: 7
#import "Basic";

#add_context tag := 0;

// Shaped like a C callback: no context, data pointer passed through by the caller.
on_event :: (value: s32, user: *void) -> s32 #c_call {
    if user {
        saved := cast(*#Context) user;
        push_context saved.* {
            print("saved context in callback: thread_index=% temp=% tag=%\n",
                context.thread_index, context.temporary_storage != null, context.tag);
        }
    } else {
        push_context {
            print("default context in callback: thread_index=% temp=% tag=%\n",
                context.thread_index, context.temporary_storage != null, context.tag);
        }
    }
    return value * 2;
}

add :: (a: int, b: int) -> int #no_context { return a + b; }   // pure leaf: no context needed

main :: () {
    context.tag = 42;
    r1 := on_event(3, null);
    saved := context;                    // keep it alive while the callback may run
    r2 := on_event(10, *saved);
    print("callback results % %\n", r1, r2);
    print("#no_context add: %\n", add(3, 4));
}
