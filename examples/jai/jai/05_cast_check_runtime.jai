// EXPECT-EXIT: 1
// EXPECT-CONTAINS: about to narrow 1000 into a u8
// EXPECT-CONTAINS: Cast bounds check failed.  Number must be in [0, 255]; it was 1000.
// EXPECT-CONTAINS: Panic.
// A narrowing cast of a value that does not fit stops a debug build with a message on stderr
// and a nonzero exit (here 1). Build with -o (or -od) and the check is compiled out: the cast
// silently keeps the low bits instead. Use cast,no_check / cast,trunc when truncation is intended.

#import "Basic";

main :: () {
    args := get_command_line_arguments();
    value := 999 + args.count;          // 1000 at runtime, so the compiler cannot reject it
    print("about to narrow % into a u8\n", value);
    byte := cast(u8) value;             // fails the range check
    print("never printed: %\n", byte);
}
