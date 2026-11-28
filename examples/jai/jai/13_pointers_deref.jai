// EXPECT: *x is the address; p.* = 5, (.*) p = 5
// EXPECT: write through pointer: x = 6
// EXPECT: field access auto-dereferences: p.hp = 10
// EXPECT: pointer to pointer needs one explicit .*: 10
// EXPECT: pointer arithmetic steps in elements: 30
// EXPECT: index through a pointer to an array: 20
// EXPECT: null pointer is false, New gives a zeroed struct: {0, 0}
// In types `*T` means "pointer to T"; in expressions `*x` means "address of x" (Jai has no `&`).
// Dereference is postfix `p.*` or prefix `(.*) p`. The old unary `<<` still compiles in 0.2.032 but
// warns on every use and will be removed (deprecated in 0.2.022).
// `.` auto-dereferences one level for member access; arguments auto-dereference *T -> T as well.

#import "Basic";

Monster :: struct { hp: int; mana: int; }

main :: () {
    x := 5;
    p := *x;                      // p: *int
    print("*x is the address; p.* = %, (.*) p = %\n", p.*, (.*) p);
    p.* += 1;
    print("write through pointer: x = %\n", x);

    m: Monster;
    mp := *m;
    mp.hp = 10;                   // no -> operator
    print("field access auto-dereferences: p.hp = %\n", mp.hp);

    mpp := *mp;                   // **Monster
    print("pointer to pointer needs one explicit .*: %\n", mpp.*.hp);

    values := int.[10, 20, 30, 40];
    first := values.data;         // *int
    print("pointer arithmetic steps in elements: %\n", (first + 2).*);

    ap := *values;                // *[4] int
    print("index through a pointer to an array: %\n", ap.*[1]);   // write ap.*[i], not ap[i] (see 57_ff_silent_traps)

    nothing: *Monster;
    fresh := New(Monster);        // heap allocation through context.allocator
    defer free(fresh);
    print("null pointer is %, New gives a zeroed struct: %\n", ifx nothing then "true" else "false", fresh.*);
}
