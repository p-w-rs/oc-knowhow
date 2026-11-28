// EXPECT: largest: 9 1.5 200
// EXPECT: fill a [5] u8 using N from the type: [7, 7, 7, 7, 7]
// EXPECT: Stack(T=string, CAP=4) holds ["a", "b", "", ""] count 2
// EXPECT: make(int)=0 make(string).count=0
// EXPECT: baked constant: 1024
// EXPECT: lambda map: [1, 4, 9]
// `$T` in a parameter declares a compile-time type variable solved from the argument; plain `T`
// elsewhere uses it. `$N` works for values too (array sizes, `$x: int` "auto-bake" parameters).
// Each distinct set of solved values compiles one concrete copy of the procedure.
// Structs take parameters: `Stack :: struct (T: Type, CAP: int)`; `Stack($T, $C)` in a parameter matches any.
// Quick lambdas `x => expr` are polymorphic procedures (they capture nothing).
// Restrictions ($T/Base, $T/interface I), #modify and #bake_arguments are covered by jai-metaprogramming.

#import "Basic";

largest :: (xs: [] $T) -> T {
    best := xs[0];
    for xs  if it > best  best = it;
    return best;
}

fill :: (arr: *[$N] $T, value: T) {
    for 0..N-1  arr.*[it] = value;
}

Stack :: struct (T: Type, CAP: int) {
    items: [CAP] T;
    count: int;
}
push :: (s: *Stack($T, $C), v: T) {
    assert(s.count < C, "stack full");
    s.items[s.count] = v;
    s.count += 1;
}

make :: ($T: Type) -> T { x: T; return x; }

shift_left :: (x: int, $amount: int) -> int { return x << amount; }   // amount must be constant

map :: (xs: [] $T, f: (T) -> $R) -> [..] R {
    out: [..] R;
    for xs  array_add(*out, f(it));
    return out;
}

main :: () {
    print("largest: % % %\n", largest(int.[3, 9, 2]), largest(float.[1.5, -2]), largest(u8.[4, 200]));

    buf: [5] u8;
    fill(*buf, 7);
    print("fill a [5] u8 using N from the type: %\n", buf);

    s: Stack(string, 4);
    push(*s, "a");
    push(*s, "b");
    print("% holds % count %\n", type_of(s), s.items, s.count);

    print("make(int)=% make(string).count=%\n", make(int), make(string).count);
    print("baked constant: %\n", shift_left(1, 10));

    squares := map(int.[1, 2, 3], x => x * x);
    print("lambda map: %\n", squares);
}
