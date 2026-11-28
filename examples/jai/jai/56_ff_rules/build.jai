// EXPECT-COMPILE-ERROR: Entry point must not return a value.
// EXPECT-COMPILE-ERROR: Invalid directive in procedure header.
// EXPECT-COMPILE-ERROR: Here we need a constant Type, but we got an expression of type 's32'.
// EXPECT-COMPILE-ERROR: Number signedness mismatch. Type wanted: u8; type given: s64.
// EXPECT-COMPILE-ERROR: In a constant-expression cast, the bounds check failed. Number must be in [0, 255], but it was 300.
// EXPECT-COMPILE-ERROR: Number mismatch. Type wanted: float32; type given: s64.
// EXPECT-COMPILE-ERROR: Type mismatch between the arguments of binary operator + (left type: u8; right type: s8).
// EXPECT-COMPILE-ERROR: Conditions listed by 'case' must be constant.
// EXPECT-COMPILE-ERROR: Duplicate case.
// EXPECT-COMPILE-ERROR: This 'if' was marked #complete...
// EXPECT-COMPILE-ERROR: This expression cannot implicitly coerce to bool
// EXPECT-COMPILE-ERROR: unary '.' dereference that was never resolved
// EXPECT-COMPILE-ERROR: Not enough values provided in this struct literal.
// EXPECT-COMPILE-ERROR: Can't assign to a large-value iterator. Perhaps you want to iterate by pointer, using 'for *'.
// EXPECT-COMPILE-ERROR: Cannot call into a native procedure, from a #c_call procedure, without using push_context
// EXPECT-COMPILE-ERROR: Subscript is out of array bounds. (The attempted index is 7, but the highest valid index is 3.)
// EXPECT-COMPILE-ERROR: Attempt to assign to a constant.
// EXPECT-COMPILE-ERROR: Redeclaration of 'x'.
// EXPECT-COMPILE-ERROR: Operator '>' does not work on strings. (Only == and != can be used on strings.)
// EXPECT-COMPILE-ERROR: Incorrect number of arguments supplied to 'print': The format string requires 2 arguments, but 1 argument is given.
// EXPECT-COMPILE-ERROR: This declaration is inside an enum marked as #specified, but it does not provide an explicit value.
// EXPECT-COMPILE-ERROR: Operator '+' does not work on strings. (Only == and != can be used on strings.)
// Rules of the language that surprise newcomers, each shown by the error it produces (beta 0.2.032).
// Every snippet compiles in its own workspace, so one `jai build.jai` reports all of them.
// The last snippet needs the Check plugin (print argument counting): the default metaprogram adds it to
// its own target workspace only, so this build file attaches it to that one workspace by hand. It must
// stay last: the plugin reports its error through compiler_report, which ends this #run, so workspaces
// created after it would never be compiled.

#import "Basic";
#import "Compiler";
#import "Metaprogram_Plugins";

RULES :: string.[
    "main :: () -> s32 { return 2; }",                                       // main returns nothing: use exit(n)
    "f :: () -> int #must { return 3; } main :: () { f(); }",                // #must is gone (removed 0.2.022)
    "main :: () { x: s32; n := size_of(x); }",                               // size_of takes a Type: size_of(type_of(x))
    "main :: () { a: u8 = 300; }",                                           // literal out of range (odd wording: 'signedness')
    "main :: () { a := cast(u8) 300; }",                                     // constant casts are range-checked at compile time
    "main :: () { i := 3; f: float = i; }",                                  // int -> float needs a cast
    "main :: () { a: u8 = 1; b: s8 = 1; c := a + b; }",                      // no implicit mixing of signedness
    "main :: () { x, y := 3, 3; if x == { case y; } }",                      // case values must be constants
    "main :: () { x := 3; if x == { case 3; case 3; } }",                    // no duplicate cases
    "E :: enum { A; B; } main :: () { e := E.A; if #complete e == { case .A; } }", // #complete: every member needed
    "T :: struct { a: int; } main :: () { t: T; if t {} }",                  // structs are not truthy
    "E :: enum { A; B; } main :: () { z := .A; }",                           // unary dot needs a known enum type
    "V :: struct { x, y, z: float; } main :: () { v := V.{1, 2}; }",         // positional literals give every member
    "V :: struct { a: int; } main :: () { arr: [2] V; for arr { it.a = 1; } }", // `it` is read-only: for * arr
    "#import \"Basic\"; cb :: () #c_call { print(\"x\"); } main :: () {}",   // #c_call has no context: push_context {}
    "main :: () { arr: [4] int; arr[7] = 1; }",                              // constant index checked at compile time
    "main :: () { LIT :: int.[1, 2]; LIT[0] = 9; }",                         // constants are immutable
    "main :: () { x := 5; x := 6; }",                                        // := declares; = assigns
    "largest :: (a: $T, b: T) -> T { return ifx a > b then a else b; } main :: () { s := largest(\"a\", \"b\"); }", // strings: use compare()
    "E :: enum u8 #specified { A :: 1; B; } main :: () {}",                  // #specified: every value explicit
    "main :: () { first := \"con\"; both := first + \"cat\"; }",               // no string +: join(), tprint("%%", a, b)
    "#import \"Basic\"; main :: () { print(\"% %\", 1); }",                  // Check plugin counts print arguments (keep LAST, see below)
];

#run {
    set_build_options_dc(.{do_output = false});
    for RULES {
        w := compiler_create_workspace(tprint("rule %", it_index));
        options := get_build_options(w);
        options.output_type = .NO_OUTPUT;
        set_build_options(options, w);
        if it_index == RULES.count - 1 {
            check_print_arguments(w, it);
        } else {
            add_build_string(it, w);
        }
    }
}

// Attach the Check plugin to workspace w and compile `code` there. The default metaprogram only gives
// Check to its own target workspace, so a build file has to drive the plugin's hooks itself.
check_print_arguments :: (w: Workspace, code: string) {
    wanted: [1] Plugin_To_Create;
    wanted[0].name = "Check";
    created: [..] *Metaprogram_Plugin;
    if !init_plugins(wanted, *created, w)  { log_error("could not start the Check plugin"); return; }
    check := created[0];

    flags: Intercept_Flags;
    if check.before_intercept  check.before_intercept(check, *flags);
    compiler_begin_intercept(w, flags);
    if check.add_source  check.add_source(check);
    add_build_string(code, w);

    done := false;
    while !done {
        msg := compiler_wait_for_message();
        if check.message  check.message(check, msg);    // Check reports print() argument mismatches here
        done = msg.kind == .COMPLETE;
    }
    compiler_end_intercept(w);
    if check.finish    check.finish(check);
    if check.shutdown  check.shutdown(check);
}
