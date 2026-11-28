// The `,,` operator changes context fields for one call only (it is sugar for push_context).
// Any context field works, including your own from #add_context; a bare Allocator after ,, means
// `allocator =`. Useful with metaprogramming because generated or library code picks up the change
// without new parameters.
// EXPECT: top
// EXPECT:     nested (depth 2 for this call only)
// EXPECT: top again
// EXPECT: built on temp: a-b-c, heap allocator untouched: true
// EXPECT: [quiet logger] value is 7

#import "Basic";
#import "String";

#add_context depth: int;

say :: (msg: string) {
    for 1..context.depth print("  ");
    print("%\n", msg);
}

quiet_logger :: (message: string, data: *void, info: Log_Info) {
    print("[quiet logger] %", message);
}

main :: () {
    say("top");
    say("nested (depth 2 for this call only)",, depth = 2);
    say("top again");

    before := context.allocator;
    s := join("a", "b", "c", separator = "-",, temp);      // allocated with the temporary allocator
    print("built on temp: %, heap allocator untouched: %\n", s, context.allocator.proc == before.proc);

    log("value is %\n", 7,, logger = quiet_logger);
}
