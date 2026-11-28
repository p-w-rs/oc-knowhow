// EXPECT: overloads: int 3 | string x | float 1.5 | area 6 16
// EXPECT: a + b = {4, 6}
// EXPECT: a * 2 = {2, 4}, 2 * a = {2, 4}
// EXPECT: c += a -> {5, 8}
// EXPECT: == and derived !=: true true
// EXPECT: ring buffer via operator *[]: [0, 7, 3, 0]
// Several procedures may share a name; the call picks one by argument types and count.
// `operator +`, `-`, `*`, `/`, `==`, `<`, ..., `[]`, `[]=`, `*[]` may be defined when at least one
// operand is a struct. `x += y` falls back to `+`, `!=` falls back to `==`.
// #symmetric lets a two-argument operator be called with the arguments swapped.
// `operator *[]` returns a pointer to the element and gives reads, writes and compound assignment.

#import "Basic";

describe :: (x: int)    -> string { return tprint("int %", x); }
describe :: (x: string) -> string { return tprint("string %", x); }
describe :: (x: float)  -> string { return tprint("float %", x); }
area :: (w: float, h: float) -> float { return w * h; }
area :: (side: float) -> float { return side * side; }

V2 :: struct { x, y: float; }
operator +  :: (a: V2, b: V2) -> V2 { return .{a.x + b.x, a.y + b.y}; }
operator *  :: (a: V2, s: float) -> V2 #symmetric { return .{a.x * s, a.y * s}; }
operator == :: (a: V2, b: V2) -> bool { return a.x == b.x && a.y == b.y; }

Ring :: struct { data: [4] int; }
operator *[] :: (r: *Ring, i: int) -> *int { return *r.data[i % 4]; }

main :: () {
    print("overloads: % | % | % | area % %\n", describe(3), describe("x"), describe(1.5), area(2, 3), area(4));

    a := V2.{1, 2};
    b := V2.{3, 4};
    print("a + b = %\n", a + b);
    print("a * 2 = %, 2 * a = %\n", a * 2, 2 * a);
    c := a + b;
    c += a;
    print("c += a -> %\n", c);
    print("== and derived !=: % %\n", a == V2.{1, 2}, a != b);

    r: Ring;
    r[5] = 7;          // index wraps to 1
    r[6] += 3;         // index wraps to 2
    print("ring buffer via operator *[]: %\n", r.data);
}
