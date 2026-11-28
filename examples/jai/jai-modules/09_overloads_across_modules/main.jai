// Same-named procedures from different unqualified imports join one overload set.
// That is fine while their argument lists differ. If two had identical argument
// lists, the call would be ambiguous: name the imports (Ints.scale) instead.
// EXPECT: 6 1.5
// EXPECT: 6 1.5

#import "Basic";
#import "Int_Tools";      // scale :: (x: int) -> int
#import "Float_Tools";    // scale :: (x: float) -> float

Ints   :: #import "Int_Tools";    // importing again under a name is free (deduplicated)
Floats :: #import "Float_Tools";

main :: () {
    print("% %\n", scale(3), scale(3.0));
    print("% %\n", Ints.scale(3), Floats.scale(3.0));
}
