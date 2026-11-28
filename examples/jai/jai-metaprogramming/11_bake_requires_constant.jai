// A `$` before an argument NAME demands a compile-time constant at every call site.
// Passing a variable is an error; use `$$` if both constant and runtime calls should work.
// EXPECT-COMPILE-ERROR: requires a value bake

#import "Basic";

table_of :: ($n: int) -> [n] int {
    t: [n] int;
    for 0..n-1 t[it] = it;
    return t;
}

main :: () {
    size := 4;
    t := table_of(size);      // fix: table_of(4), or declare `size :: 4;`
    print("%\n", t);
}
