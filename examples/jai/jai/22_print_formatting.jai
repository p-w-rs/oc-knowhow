// EXPECT: plain % per argument: 1 two 3.5
// EXPECT: adjacent with %%: leftright
// EXPECT: literal percent: 100%
// EXPECT: reordered: second first first
// EXPECT: %0 is the next argument: 78x
// EXPECT: hex ff, padded 007, commas 1,234,567, struct-literal form 00ff
// EXPECT: floats: 0.333333 | 0.33 | 2.500 | 1.234568e+04
// EXPECT: struct {1, 2.5, "pt"} | long form {x = 1; y = 2.5; name = "pt"; }
// EXPECT: containers: [1, 2, 3] ["a", "b"] [] null
// EXPECT: values: true GREEN A | C s64 65
// EXPECT: to stderr too
// EXPECT: default base changed for this block: ff
// print(format, ..args): every `%` takes the next argument and prints it according to its type.
// No printf-style specifiers: format a value by wrapping it (formatInt, formatFloat, formatStruct, or
// the struct literals FormatInt.{...}, FormatFloat.{...}). `%N` picks argument N (1-based), `%0` the next one.
// Since 0.2.022 `%%` means two arguments back to back; a literal percent is `\%`.
// sprint returns a heap string, tprint a temporary-storage string, print(*builder, ...) appends.
// The Check plugin (on by default) reports a wrong number of % at compile time.

#import "Basic";

V :: struct { x: float; y: float; name: string; }
Color :: enum { RED; GREEN; }
Flags :: enum_flags u8 { A; B; C; }

main :: () {
    print("plain \% per argument: % % %\n", 1, "two", 3.5);
    print("adjacent with \%\%: %%\n", "left", "right");
    print("literal percent: 100\%\n");
    print("reordered: %2 %1 %1\n", "first", "second");
    print("\%0 is the next argument: %1%0x\n", 7, 8);

    print("hex %, padded %, commas %, struct-literal form %\n",
          formatInt(255, base = 16), formatInt(7, minimum_digits = 3),
          formatInt(1234567, digits_per_comma = 3, comma_string = ","),
          FormatInt.{value = 255, base = 16, minimum_digits = 4});

    third := 1.0 / 3.0;
    print("floats: % | % | % | %\n", third, formatFloat(third, trailing_width = 2),
          formatFloat(2.5, trailing_width = 3, zero_removal = .NO), formatFloat(12345.678, mode = .SCIENTIFIC));

    v := V.{1, 2.5, "pt"};
    print("struct % | long form %\n", v, formatStruct(v, use_long_form_if_more_than_this_many_members = 0));

    empty: [..] int;
    nothing: *int;
    print("containers: % % % %\n", int.[1, 2, 3], string.["a", "b"], empty, nothing);
    print("values: % % % % %\n", true, Color.GREEN, Flags.A | .C, type_of(3), #char "A");

    print("to stderr too\n", to_standard_error = false);   // set true to write to stderr

    c := context;
    c.print_style.default_format_int.base = 16;            // change defaults for a subtree
    push_context c { print("default base changed for this block: %\n", 255); }
}
