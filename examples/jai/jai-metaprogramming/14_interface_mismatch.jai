// An interface restriction is checked at the call: a struct without the required members is rejected
// with a clear error at the call site, instead of a confusing error deep inside the body.
// EXPECT-COMPILE-ERROR: The given type does not match the required interface.

#import "Basic";

Has_Size :: struct { w, h: float; }
area :: (s: $T/interface Has_Size) -> float { return s.w * s.h; }

Circle :: struct { radius: float; }     // has no w and h

main :: () {
    print("%\n", area(Circle.{2}));
}
