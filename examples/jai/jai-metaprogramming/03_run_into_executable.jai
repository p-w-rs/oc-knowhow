// What survives from compile time into the executable.
// 1. Values returned by #run are serialized as constants: numbers, strings, Types, enums, fixed arrays
//    and structs of those are fine.
// 2. Globals are RESET to their declared values when the executable is written, so state set by #run
//    does not leak; `#no_reset` keeps the compile-time value (plain data only).
// 3. Pointers into memory the #run allocated cannot travel: the compiler warns and the pointer would
//    crash at run time. Unions cannot travel either: even a tagged union (0.2.023+) only gets a
//    warning, and its payload is LOST (built as {INT, 42}, arrives as {INT, 0} in 0.2.032).
// EXPECT-COMPILE: [compile time] counter=5, squares[9]=81
// EXPECT-COMPILE: Warning: Returned a pointer literal from compile-time execution that could not be mapped to a global variable
// EXPECT-COMPILE: Warning: It is illegal to return an untagged union from compile-time execution
// EXPECT: ELEMENT = float64, TABLE = [1, 2, 4, 8], named = {2, ["a", "b"]}
// EXPECT: counter (reset) = 0
// EXPECT: squares (#no_reset) = [0, 1, 4, 9, 16, 25, 36, 49, 64, 81]
// EXPECT: stats (#no_reset) = 10 entries, total 285
// EXPECT: node.value = 7 (node.next must not be used)
// EXPECT: tagged union from #run: {INT, 0} (built as {INT, 42})

#import "Basic";

ELEMENT :: #run -> Type { return float64; };
TABLE   :: #run -> [4] int { t: [4] int; for 0..3 t[it] = 1 << it; return t; };

Named :: struct { count: int; names: [2] string; }
named :: #run Named.{2, .["a", "b"]};

counter: int;                                    // reset to 0 in the executable
#no_reset squares: [10] int;                     // keeps what #run computed
#no_reset stats: struct { entries: int; total: int; };

#run {
    counter = 5;
    for 0..9 {
        squares[it] = it * it;
        stats.total += it * it;
    }
    stats.entries = squares.count;
    print("[compile time] counter=%, squares[9]=%\n", counter, squares[9]);
}

Node :: struct { value: int; next: *Node; }
make_node :: () -> Node {
    n: Node;
    n.value = 7;
    n.next  = New(Node);       // heap memory of the compiler process
    return n;
}
node :: #run make_node();      // warning: the pointer cannot be mapped

Kind  :: enum u8 { INT; TEXT; }
Value :: union kind: Kind { .INT ,, i: int; .TEXT ,, s: string; }
make_value :: () -> Value { v: Value = .{.INT, 42}; return v; }
VALUE :: #run make_value();    // warning, and the payload does not survive

main :: () {
    print("ELEMENT = %, TABLE = %, named = %\n", ELEMENT, TABLE, named);
    print("counter (reset) = %\n", counter);
    print("squares (#no_reset) = %\n", squares);
    print("stats (#no_reset) = % entries, total %\n", stats.entries, stats.total);
    print("node.value = % (node.next must not be used)\n", node.value);
    print("tagged union from #run: % (built as {INT, 42})\n", VALUE);
}
