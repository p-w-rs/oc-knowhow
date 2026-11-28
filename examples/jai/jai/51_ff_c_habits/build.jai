// EXPECT-COMPILE-ERROR: Error in unary expression.
// EXPECT-COMPILE-ERROR: Semicolon expected after expression.
// EXPECT-COMPILE-ERROR: If you want to declare a variable, try "x: int;"
// EXPECT-COMPILE-ERROR: If you want to declare a variable, try "x: auto;"
// EXPECT-COMPILE-ERROR: If you want to declare a variable, try "x: switch;"
// EXPECT-COMPILE-ERROR: We parsed a declaration, so we expected a semicolon after it, but saw this instead.
// EXPECT-COMPILE-ERROR: ',' expected.
// EXPECT-COMPILE-ERROR: Unable to parse a statement here.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'NULL'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'nullptr'.
// EXPECT-COMPILE-ERROR: Expected an expression after '='.
// EXPECT-COMPILE-ERROR: Invalid toplevel directive name 'include'
// EXPECT-COMPILE-ERROR: Operator '=' can only be used at statement level.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'sizeof'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'printf'.
// EXPECT-COMPILE-ERROR: Number signedness mismatch. Type wanted: u32; type given: s64.
// EXPECT-COMPILE-ERROR: Type mismatch. Type wanted: bool; type given: s64.
// A bench of C, C++ and Go habits, each compiled in its own workspace so ONE `jai build.jai`
// reports every error (a single file stops at its first error). Each line below was verified with
// beta 0.2.032; the message it produces is in the comment. Several habits share a message.
// The Jai way is in brackets. Run it yourself to see where each error points.

#import "Basic";
#import "Compiler";

HABITS :: string.[
    "main :: () { i := 0; i++; }",                                    // Error in unary expression.            [i += 1;]
    "V :: struct { a: int; } main :: () { v: V; p := *v; p->a = 1; }", // Semicolon expected after expression. [p.a = 1;]
    "main :: () { int x = 5; }",                                      // C-style declaration, try "x: int;"     [x: int = 5; / x := 5;]
    "main :: () { auto x = 5; }",                                     // C-style declaration, try "x: auto;"    [x := 5;]
    "main :: () { x := 1; switch x { case 1: } }",                    // C-style declaration, try "x: switch;"  [if x == { case 1; }]
    "main :: () { x := 3; y := x > 2 ? 1 : 0; }",                     // We parsed a declaration ...           [ifx x > 2 then 1 else 0]
    "main :: () { x := 1e5; }",                                       // same message: exponents need a dot     [1.0e5]
    "main :: () { for (i := 0; i < 3; i += 1) {} }",                  // ',' expected.                         [for i: 0..2 {}]
    "main :: () { n := 3; for i := 0; i < n; i += 1 {} }",            // Unable to parse a statement here.     [for i: 0..n-1 {}]
    "main :: () { p: *int = NULL; }",                                 // Undeclared identifier 'NULL'.          [null]
    "main :: () { p := nullptr; }",                                   // Undeclared identifier 'nullptr'.       [null]
    "main :: () { c := 'a'; }",                                       // Expected an expression after '='.     [#char "a"]
    "#include \"stdio.h\"\nmain :: () {}",                            // Invalid toplevel directive name 'include' [#import / #load]
    "main :: () { a, b: int; a = b = 0; }",                           // Operator '=' can only be used at statement level. [a, b = 0;]
    "main :: () { x := 1; if (x = 5) {} }",                           // same message: no assignment in conditions [x == 5]
    "main :: () { x := 1; do { x += 1; } while (x < 3); }",           // Semicolon expected after expression.  [while + defer]
    "main :: () { x: int; n := sizeof(x); }",                         // Undeclared identifier 'sizeof'.        [size_of(type_of(x))]
    "#import \"Basic\"; main :: () { printf(\"%d\", 1); }",           // Undeclared identifier 'printf'.        [print("%", 1)]
    "main :: () { all_ones: u32 = -1; }",                             // Number signedness mismatch ... u32    [0xFFFF_FFFF or cast,no_check]
    "main :: () { flag: bool = 1; }",                                 // Type mismatch. Type wanted: bool      [true]
];

#run {
    set_build_options_dc(.{do_output = false});
    for HABITS {
        w := compiler_create_workspace(tprint("C habit %", it_index));
        options := get_build_options(w);
        options.output_type = .NO_OUTPUT;     // type-check only; nothing to link
        set_build_options(options, w);
        add_build_string(it, w);
    }
}
