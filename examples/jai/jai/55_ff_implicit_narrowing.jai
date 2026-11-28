// EXPECT-COMPILE-ERROR: Loss of information (trying to fit 64 bits into 32 bits). Can't do this without an explicit cast.
// C habit: implicit narrowing (and C/Go-style mixing of signed/unsigned). Jai only converts implicitly
// when every source value fits the target (u8 -> s32 yes, s64 -> s32 no, s8 -> u64 no, int -> float no).
// Literals and :: constants are the exception: they convert if their value fits.

#import "Basic";

main :: () {
    a: s64 = 10;
    b: s32 = a;                     // Jai: b: s32 = xx a;  (range-checked in debug builds)
    print("%\n", b);
}
