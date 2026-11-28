// print is Basic's printf: every argument goes where a bare % is; there are no
// %d/%s/%f codes. Formatting options come from wrapping a value in a FormatInt /
// FormatFloat literal (formatInt()/formatFloat() are older helper procedures that
// still work).
// EXPECT: 42 3.5 str
// EXPECT: reorder: b a b
// EXPECT: empty: [] literal percent: 100%
// EXPECT: [00042] [ff] [1,234,567]
// EXPECT: [3.14] [   0.333] [1.234568e+04]
// EXPECT: older helpers: [007] [3.14]
// EXPECT: {1, 2.5, "p"}
// EXPECT: {a = 1; b = 2; c = 3; d = 4; e = 5; f = 6; }
// EXPECT: PEAR READ | EXEC
// EXPECT: [1, 2, 3] true null
// EXPECT: Point [3] s64
// EXPECT: 2.5e10 as a float32 literal prints 24999999488
// EXPECT: write_string does no formatting: %

#import "Basic";

Point :: struct { x: int; y: float; name: string; }
Six   :: struct { a, b, c, d, e, f: int; }
Fruit :: enum { APPLE; PEAR; }
Perm  :: enum_flags { READ; WRITE; EXEC; }

main :: () {
    print("% % %\n", 42, 3.5, "str");
    print("reorder: %2 %1 %2\n", "a", "b");        // %N picks argument N (1-based)
    print("empty: [%00] literal percent: 100\%\n"); // %00 prints nothing; \% is a literal %
    print("[%] [%] [%]\n",
        FormatInt.{value = 42, minimum_digits = 5},
        FormatInt.{value = 255, base = 16},
        FormatInt.{value = 1234567, digits_per_comma = 3, comma_string = ","});
    print("[%] [%] [%]\n",
        FormatFloat.{value = 3.14159, trailing_width = 2},
        FormatFloat.{value = 1.0/3.0, width = 8, trailing_width = 3},
        FormatFloat.{value = 12345.678, mode = .SCIENTIFIC});
    print("older helpers: [%] [%]\n", formatInt(7, minimum_digits = 3), formatFloat(3.14159, trailing_width = 2));

    print("%\n", Point.{1, 2.5, "p"});          // short form up to 5 members
    print("%\n", Six.{1, 2, 3, 4, 5, 6});        // long form with names beyond that
    print("% %\n", Fruit.PEAR, Perm.READ | .EXEC);
    print("% % %\n", int.[1, 2, 3], true, cast(*int) null);
    print("% %\n", Point, type_of(int.[1, 2, 3]));
    print("2.5e10 as a float32 literal prints %\n", 2.5e10);  // untyped float literals default to float32
    write_string("write_string does no formatting: %\n");
}
