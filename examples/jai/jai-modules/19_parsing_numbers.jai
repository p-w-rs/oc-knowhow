// Text to numbers. Basic: to_integer, string_to_int (with base) and string_to_float
// return (value, success, remainder); string_to_float_new (0.2.027) returns
// (success, value, remainder), the success-first order newer APIs use (table_find,
// Math inverse); prefer it in new code. String: parse_int / parse_float /
// parse_token advance a *string cursor, good for scanning a line field by field.
// EXPECT: to_integer("123abc") = 123 true, rest "abc"
// EXPECT: string_to_int("ff", 16) = 255 true
// EXPECT: string_to_float_new("2.75 meters") = true 2.75, rest " meters"
// EXPECT: parse_int: 17 true, -4 true, cursor now "  rest"
// EXPECT: parse_token: "name" true, cursor now " = value"
// EXPECT: bad input: 0 false

#import "Basic";
#import "String";

main :: () {
    n, ok, rest := to_integer("123abc");
    print("to_integer(\"123abc\") = % %, rest \"%\"\n", n, ok, rest);
    h, ok_h := string_to_int("ff", 16);
    print("string_to_int(\"ff\", 16) = % %\n", h, ok_h);
    ok_f, f, rest_f := string_to_float_new("2.75 meters");
    print("string_to_float_new(\"2.75 meters\") = % %, rest \"%\"\n", ok_f, f, rest_f);

    cursor := "  17 -4  rest";
    a, ok_a := parse_int(*cursor);
    b, ok_b := parse_int(*cursor);
    print("parse_int: % %, % %, cursor now \"%\"\n", a, ok_a, b, ok_b, cursor);

    t := "name = value";
    token, ok_t := parse_token(*t);
    print("parse_token: \"%\" %, cursor now \"%\"\n", token, ok_t, t);

    bad, ok_bad := to_integer("xyz");
    print("bad input: % %\n", bad, ok_bad);
}
