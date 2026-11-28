// Four ways to change the context, and how long each change lasts.
// 1. context.x = v      plain assignment: NOT scoped to a block, and it flows back up to the caller.
// 2. push_context c {}  a whole new context for the block, restored afterwards.
// 3. f(args,, x = v)    call-site override: changed before the call, restored after it.
// 4. push_allocator(a)  a Basic macro that sets context.allocator until the end of the enclosing scope.
// Plus: push_context,defer_pop c;  pushes for the rest of the current scope.
// EXPECT: 1. after the block: 10
// EXPECT: 1. after a callee changed it: 11
// EXPECT: 2. inside push_context: 50
// EXPECT: 2. after push_context: 11
// EXPECT: 3. callee sees 77
// EXPECT: 3. after the call: 11
// EXPECT: 3. New(int,, temp) came from temporary storage: true
// EXPECT: 4. inside: allocator is temp = true
// EXPECT: 4. after scope: allocator is temp = false
// EXPECT: 5. after push_context,defer_pop: 5
// EXPECT: 5. back in main: 11
#import "Basic";

#add_context level := 0;

bump :: () { context.level += 1; }       // a callee that "leaks" a change upward
show :: (label: string) { print("% %\n", label, context.level); }

defer_pop_demo :: () {
    c := context;
    c.level = 5;
    push_context,defer_pop c;            // active until this procedure returns
    print("5. after push_context,defer_pop: %\n", context.level);
}

main :: () {
    {
        context.level = 10;              // no restore at the closing brace!
    }
    print("1. after the block: %\n", context.level);
    bump();
    print("1. after a callee changed it: %\n", context.level);

    c := context;                        // copy, edit, push
    c.level = 50;
    push_context c {
        print("2. inside push_context: %\n", context.level);
    }
    print("2. after push_context: %\n", context.level);

    show("3. callee sees",, level = 77);
    print("3. after the call: %\n", context.level);
    p := New(int,, temp);                // the usual way to pick an allocator for one call
    print("3. New(int,, temp) came from temporary storage: %\n", temporary_allocator_proc(.IS_THIS_YOURS, 0, 0, p, null) != null);

    {
        push_allocator(temp);
        print("4. inside: allocator is temp = %\n", context.allocator.proc == temp.proc);
    }
    print("4. after scope: allocator is temp = %\n", context.allocator.proc == temp.proc);

    defer_pop_demo();
    print("5. back in main: %\n", context.level);
}
