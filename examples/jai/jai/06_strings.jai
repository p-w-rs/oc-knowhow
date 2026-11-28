// EXPECT: count=13 first byte=72 (u8)
// EXPECT: view without copying: 'Sailor'
// EXPECT: equal=true compare=-1 starts=true contains=true comma at 5
// EXPECT: split: ["a", "b", "", "c"]
// EXPECT: join: 'xyz' and 'x-y-z'
// EXPECT: C string has 13 bytes before the zero
// EXPECT: back to a string: 'Hello, Sailor'
// EXPECT: sprint: '2 + 3 = 5', builder: 'abc-7-'
// EXPECT: copy can be modified: Mutable
// EXPECT: to_integer: 456 true rest 'xyz'
// EXPECT: empty string is false
// `string` is a view: { count: s64; data: *u8; }. It is NOT zero-terminated, assignment never copies
// the bytes, and indexing gives a u8. String utilities live in module String; to_c_string,
// copy_string, sprint/tprint and String_Builder are in Basic.

#import "Basic";
#import "String";

c_length :: (p: *u8) -> int {           // what a C library would do with the pointer
    n := 0;
    while p[n]  n += 1;
    return n;
}

main :: () {
    s := "Hello, Sailor";
    print("count=% first byte=% (%)\n", s.count, s[0], type_of(s[0]));

    tail := s;                            // copies the 16-byte view, not the characters
    tail.data += 7;
    tail.count -= 7;
    print("view without copying: '%'\n", tail);

    print("equal=% compare=% starts=% contains=% comma at %\n",
          s == "Hello, Sailor", compare("abc", "abd"), begins_with(s, "Hell"), contains(s, "Sail"),
          find_index_from_left(s, #char ","));

    print("split: %\n", split("a,b,,c", ","));
    print("join: '%' and '%'\n", join("x", "y", "z"), join(..string.["x", "y", "z"], separator = "-"));

    c := to_c_string(s);                  // allocates count+1 bytes and writes the terminating zero
    defer free(c);
    print("C string has % bytes before the zero\n", c_length(c));
    print("back to a string: '%'\n", to_string(c));   // wraps the pointer, no copy

    built := sprint("% + % = %", 2, 3, 5);            // heap; tprint would use temporary storage
    defer free(built);
    builder: String_Builder;
    append(*builder, "abc");
    print_to_builder(*builder, "-%-", 7);
    print("sprint: '%', builder: '%'\n", built, builder_to_string(*builder));

    copy := copy_string("mutable");       // literals live in read-only memory; copy before editing
    copy[0] = #char "M";
    print("copy can be modified: %\n", copy);

    value, ok, rest := to_integer("456xyz");
    print("to_integer: % % rest '%'\n", value, ok, rest);

    empty: string;
    if !empty  print("empty string is false\n");
}
