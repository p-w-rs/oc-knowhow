// EXPECT: widening is implicit: 200 -> 200
// EXPECT: cast(u8) 200 = 200
// EXPECT: cast,no_check(u8) 300 = 44, cast,trunc(u8) 300 = 44
// EXPECT: xx picks the target type: 99
// EXPECT: float to int truncates toward zero: 3 -3
// EXPECT: int to float: 7 (float32)
// EXPECT: bool from numbers: false true, pointer null is false
// Conversions between numeric types are explicit unless the target holds every value of the source.
//   cast(T) x          checked conversion (range-checked at runtime in debug builds)
//   xx x               "auto-cast": cast to whatever type the context needs (also range-checked)
//   cast,no_check(T) x  skip the range check (keep the low bits)
//   cast,trunc(T) x    deliberate truncation, also unchecked
// The runtime check is in 05_cast_check_runtime.jai; the compile-time errors are in 50+ false-friend examples.

#import "Basic";

takes_u8 :: (v: u8) -> u8 { return v; }

main :: () {
    small: u8 = 200;
    wide: u32 = small;                       // u8 fits in u32: no cast needed
    print("widening is implicit: % -> %\n", small, wide);

    n: s64 = 200;
    print("cast(u8) 200 = %\n", cast(u8) n);

    big: s64 = 300;
    print("cast,no_check(u8) 300 = %, cast,trunc(u8) 300 = %\n", cast,no_check(u8) big, cast,trunc(u8) big);

    m: s64 = 99;
    print("xx picks the target type: %\n", takes_u8(xx m));

    f: float = 3.9;  g: float = -3.9;
    print("float to int truncates toward zero: % %\n", cast(int) f, cast(int) g);

    k := 7;
    fk := cast(float) k;
    print("int to float: % (%)\n", fk, type_of(fk));

    p: *int;
    print("bool from numbers: % %, pointer null is %\n", cast(bool) 0, cast(bool) 5, cast(bool) p);
}
