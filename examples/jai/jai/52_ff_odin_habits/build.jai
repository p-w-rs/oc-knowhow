// EXPECT-COMPILE-ERROR: ')' expected.
// EXPECT-COMPILE-ERROR: Unable to parse type instantiation.
// EXPECT-COMPILE-ERROR: If you want to declare a variable, try "main: package;"
// EXPECT-COMPILE-ERROR: To instantiate a type with arguments, that type must be a struct.
// EXPECT-COMPILE-ERROR: If you want to declare a variable, try "arr: in;"
// EXPECT-COMPILE-ERROR: Undeclared identifier 'dynamic'.
// EXPECT-COMPILE-ERROR: Semicolon expected after expression.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'len'.
// EXPECT-COMPILE-ERROR: We parsed a declaration, so we expected a semicolon after it, but saw this instead.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'nil'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'new'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'make'.
// EXPECT-COMPILE-ERROR: Procedure call did not match any of the possible overloads.
// EXPECT-COMPILE-ERROR: Expected an expression after '..'.
// EXPECT-COMPILE-ERROR: Expected '{' after 'struct'.
// A bench of Odin habits (Odin is close to Jai in spirit, so these slip in easily). Each snippet is
// compiled in its own workspace so one `jai build.jai` shows every error. Messages verified with
// beta 0.2.032 are in the comments, the Jai spelling in brackets.

#import "Basic";
#import "Compiler";

HABITS :: string.[
    "add :: proc(a: int, b: int) -> int { return a + b; } main :: () {}", // ')' expected.               [add :: (a: int, b: int) -> int {...}]
    "main :: () { x := 5; p: ^int = *x; }",                         // Unable to parse type instantiation. [p: *int = *x;]
    "package main\nmain :: () {}",                                   // C-style declaration "main: package;" [no package line; files are #load-ed]
    "main :: () { big := 300; small := u8(big); }",                  // must be a struct                  [cast(u8) big / xx big]
    "main :: () { arr: [3] int; for x in arr {} }",                  // C-style declaration "arr: in;"    [for x: arr {}]
    "main :: () { d: [dynamic] int; }",                              // Undeclared identifier 'dynamic'.  [d: [..] int;]
    "import \"core:fmt\"\nmain :: () { fmt.println(\"hi\"); }",      // Semicolon expected after expression. [#import "Basic"; print("hi\n");]
    "main :: () { when true { } }",                                  // same message                      [#if true { }]
    "main :: () { arr: [3] int; n := len(arr); }",                   // Undeclared identifier 'len'.      [arr.count]
    "main :: () { x: int; y := x or_return; }",                      // We parsed a declaration ...       [multiple returns + explicit if]
    "Meters :: distinct f64; main :: () {}",                         // same message                      [Meters :: #type,distinct float64;]
    "main :: () { p: *int = nil; }",                                 // Undeclared identifier 'nil'.      [null]
    "main :: () { p := new(int); }",                                 // Undeclared identifier 'new'.      [New(int)]
    "main :: () { a := make([] int, 10); }",                         // Undeclared identifier 'make'.     [NewArray(10, int)]
    "#import \"Basic\"; main :: () { arr: [..] int; append(*arr, 5); }", // no overload: Basic's append is for String_Builder [array_add(*arr, 5)]
    "main :: () { for i: 0..<10 {} }",                               // Expected an expression after '..'. [for i: 0..9 {}]
    "S :: struct #packed { a: u8; b: u32; } main :: () {}",          // Expected '{' after 'struct'.     [b: u32 #align 1; and/or `} #no_padding` after the brace]
];

#run {
    set_build_options_dc(.{do_output = false});
    for HABITS {
        w := compiler_create_workspace(tprint("Odin habit %", it_index));
        options := get_build_options(w);
        options.output_type = .NO_OUTPUT;
        set_build_options(options, w);
        add_build_string(it, w);
    }
}
