// #assert checks a constant condition while compiling. The message comes after the condition,
// without a comma: `#assert cond "message";`. Writing `#assert(cond, "message")` like C's
// static_assert is a syntax error (see 05_assert_comma_is_wrong.jai).
// This file deliberately fails: the struct grew past the size budget.
// EXPECT-COMPILE-ERROR: Compile-time assertion failed. "Packet must stay within 16 bytes"

#import "Basic";

Packet :: struct {
    id:      u32;
    flags:   u16;
    payload: [12] u8;   // 4 + 2 + 12 = 18 bytes (+ padding): too big
}

#assert size_of(Packet) <= 16 "Packet must stay within 16 bytes";

main :: () {
    print("unreachable: the build stops at the #assert\n");
}
