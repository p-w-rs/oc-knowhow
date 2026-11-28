// #insert pastes compile-time code into the program: a constant string (parsed as source) or a Code
// value. It works at statement level, at expression level (the string still ends with ';'), inside
// structs, and at file scope. `#insert #run gen()` and the short form `#insert -> string { ... }`
// generate the text with ordinary code. Generated text is saved in .build/.added_strings_w*.jai.
// EXPECT: x after inserted statement = 30
// EXPECT: y from inserted expression = 31
// EXPECT: Rgba = {r = 1, g = 0.5, b = 0.25, a = 1}
// EXPECT: unrolled: 0 1 2 3
// EXPECT: generated constant ANSWER = 42

#import "Basic";

member_list :: (names: [] string, type: string) -> string {
    sb: String_Builder;
    for names print_to_builder(*sb, "%: % = 1;\n", it, type);
    return builder_to_string(*sb);
}

// Members generated from a list of names (all default to 1).
Rgba :: struct {
    #insert #run member_list(.["r", "g", "b", "a"], "float");
}

// File scope: a declaration that only exists because a #run produced its text.
#insert #run tprint("ANSWER :: %;", 6 * 7);

// `i is declared once in the CALLER's scope (braces inside the macro would not limit it), then
// assigned before each pasted copy of the body.
unroll :: ($count: int, body: Code) #expand {
    `i: int;
    #insert -> string {
        sb: String_Builder;
        for 0..count-1 print_to_builder(*sb, "`i = %; #insert body;\n", it);
        return builder_to_string(*sb);
    }
}

main :: () {
    x := 3;
    #insert "x *= 10;";
    print("x after inserted statement = %\n", x);

    y := 1 + #insert "x;";          // expression insert: one expression, terminated by ;
    print("y from inserted expression = %\n", y);

    c: Rgba;
    c.g = 0.5; c.b = 0.25;
    print("Rgba = {r = %, g = %, b = %, a = %}\n", c.r, c.g, c.b, c.a);

    print("unrolled:");
    unroll(4, #code print(" %", i));
    print("\n");

    print("generated constant ANSWER = %\n", ANSWER);
}
