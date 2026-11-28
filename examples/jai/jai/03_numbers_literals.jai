// EXPECT: hex 255 binary 10 grouped 1000000
// EXPECT: 1.5 -> float32, 3.141592653589793 -> float64, 2.0e3 -> float32
// EXPECT: #char "A" = 65 (type s64)
// EXPECT: float bits: NaN -0
// EXPECT: s16 + u8 -> s16, u32 + s64 -> s64
// EXPECT: 7/2=3 -7/2=-3 -7%3=-1 7.0/2=3.5
// EXPECT: limits from Math: 9223372036854775807 255
// EXPECT: shifts and bits: 1099511627776 6 255
// Integer types: s8 s16 s32 s64 u8 u16 u32 u64, `int` = s64. Floats: float32 (= `float`), float64.
// Integer literals are s64 unless the target type says otherwise and the value fits.
// Float literals are float32 unless they need more digits (then float64).
// Exponent literals need a dot: 2.0e3 works, 2e3 does not parse.

#import "Basic";
#import "Math";   // S64_MAX, U8_MAX, FLOAT32_MAX, PI ... live in Math, not Basic

main :: () {
    print("hex % binary % grouped %\n", 0xFF, 0b1010, 1_000_000);

    a := 1.5;  b := 3.141592653589793;  c := 2.0e3;
    print("1.5 -> %, 3.141592653589793 -> %, 2.0e3 -> %\n", type_of(a), type_of(b), type_of(c));

    ch := #char "A";                 // a character literal is just a number
    print("#char \"A\" = % (type %)\n", ch, type_of(ch));

    nan  := 0h7FC0_0000;              // 0h: raw IEEE-754 bits (8 hex digits = float32, 16 = float64)
    nzero := 0h8000_0000_0000_0000;
    print("float bits: % %\n", nan, nzero);

    small: s16 = -5;  byte: u8 = 200;  wide: u32 = 7;  big: s64 = 3;
    print("s16 + u8 -> %, u32 + s64 -> %\n", type_of(small + byte), type_of(wide + big));

    print("7/2=% -7/2=% -7\%3=% 7.0/2=%\n", 7 / 2, -7 / 2, -7 % 3, 7.0 / 2);

    print("limits from Math: % %\n", S64_MAX, U8_MAX);

    print("shifts and bits: % % %\n", 1 << 40, 0b1100 ^ 0b1010, ~cast(u8) 0);
}
