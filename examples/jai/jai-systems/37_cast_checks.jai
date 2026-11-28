// Narrowing casts are range-checked at runtime in debug builds (cast_bounds_check = .FATAL;
// off with -o/-od). Say what you mean instead of silencing it:
//   cast,trunc(u8) x      keep the low bits on purpose (never checked)
//   cast,no_check(u8) x   skip the check (also truncates)
//   xx x                  autocast to the target type: checked like cast
// EXPECT-EXIT: 1
// EXPECT-CONTAINS: cast,trunc(u8) 300 = 44
// EXPECT-CONTAINS: cast,no_check(u8) 300 = 44
// EXPECT-CONTAINS: Cast bounds check failed.  Number must be in [0, 255]; it was 300.
#import "Basic";

main :: () {
    big: s64 = 299 + get_command_line_arguments().count;   // 300, not a compile-time constant
    print("cast,trunc(u8) % = %\n", big, cast,trunc(u8) big);
    print("cast,no_check(u8) % = %\n", big, cast,no_check(u8) big);
    small: u8 = xx big;                                     // checked: fails here
    print("not reached: %\n", small);
}
