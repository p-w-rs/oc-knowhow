// #add_context adds a field to #Context for the whole program (any file or module can do it).
// Use it for per-call-tree settings or per-thread state without passing parameters.
// The initializer runs wherever a fresh #Context is created (program start, push_context {},
// new threads); a name clash with another module's field is a compile error.
// EXPECT: indent=0 verbose=false
// EXPECT: · node a
// EXPECT: · · node b
// EXPECT: · · · node c (verbose)
// EXPECT: indent restored to 0
#import "Basic";

#add_context indent := 0;
#add_context verbose := false;

Node :: struct { name: string; child: *Node; }

dump :: (n: *Node) {
    for 1..context.indent+1 print("· ");
    print("node %", n.name);
    if context.verbose print(" (verbose)");
    print("\n");
    if n.child {
        // One level deeper only for the recursive call; restored when it returns.
        dump(n.child,, indent = context.indent + 1, verbose = n.child.child == null);
    }
}

main :: () {
    print("indent=% verbose=%\n", context.indent, context.verbose);
    c := Node.{"c", null};
    b := Node.{"b", *c};
    a := Node.{"a", *b};
    dump(*a);
    print("indent restored to %\n", context.indent);
}
