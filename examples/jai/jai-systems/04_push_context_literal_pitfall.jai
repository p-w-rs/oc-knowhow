// Pitfall in 0.2.032 (compiler bug, may be fixed later): a struct literal that names ONLY
// #add_context fields, pushed with push_context .{...}, can fail with "is not a member of Context0"
// when the program declares other procedures in a certain order (here: a zero-argument
// procedure declared before main). The same literal compiles in other files.
// Robust forms that always worked in our tests:
//     c := context; c.retries = 3; push_context c { ... }     // copy, edit, push
//     do_work(,, retries = 3);                                   // call-site override
//     push_context .{allocator = temp, retries = 3} { ... }    // literal that also names a Context_Base field
// EXPECT-COMPILE-ERROR: 'retries' is not a member of Context0
#import "Basic";

#add_context retries := 1;

do_work :: () { print("retries=%\n", context.retries); }

main :: () {
    push_context .{retries = 3} {
        do_work();
    }
}
