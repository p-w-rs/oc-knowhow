// EXPECT-COMPILE-ERROR: Procedure call did not match any of the possible overloads.
// C++/Rust(derive)/Odin habit: comparing structs with ==. Jai has no built-in struct ==; define
// `operator == :: (a: T, b: T) -> bool` (then != works too), or compare memory with memcmp for
// plain-old-data. The error lists the operator == overloads it did find (from Basic's Int128).

#import "Basic";

V2 :: struct { x, y: float; }

main :: () {
    a, b: V2;
    print("%\n", a == b);
}
