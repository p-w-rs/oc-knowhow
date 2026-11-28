// EXPECT-COMPILE-ERROR: The #place directive has been deprecated. It will no longer compile. Please use #overlay, or some other solution, instead.
// EXPECT-COMPILE-ERROR: '(' expected.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'Context'.
// EXPECT-COMPILE-ERROR: Argument name 'initialized' (number 2) is not found in the procedure being called.
// EXPECT-COMPILE-ERROR: Not enough return values: Wanted 1, got 0.
// EXPECT-COMPILE-ERROR: Type mismatch: incompatible structs (wanted 'Base', given 'Derived').
// EXPECT-COMPILE-ERROR: Mismatching levels of indirection. Type wanted: S; type given: *S
// EXPECT-COMPILE-ERROR: Cannot cast from one struct to another without force modifiers.
// EXPECT-COMPILE-ERROR: 'loose' is not a member of E.
// EXPECT-COMPILE-ERROR: Too many arguments: Wanted 1, got 2.
// EXPECT-COMPILE-ERROR: Invalid toplevel directive name 'foreign_library'
// EXPECT-COMPILE-ERROR: Invalid toplevel directive name 'foreign_system_library'
// EXPECT-COMPILE-ERROR: Invalid toplevel directive name 'run_and_insert'
// EXPECT-COMPILE-ERROR: cast(T).* was a temporary experiment from a disfavored syntax. It's no longer supported.
// EXPECT-COMPILE-ERROR: 'else' without 'if'.
// EXPECT-COMPILE-ERROR: Identifier 'K' is used before its declaration.
// EXPECT-COMPILE-ERROR: Attempt to create a struct literal, but the left-hand type is not a struct.
// EXPECT-COMPILE-ERROR: Unable to parse an expression to the right of this binary operator.
// EXPECT-COMPILE-ERROR: Unable to find a module called 'Tagged_Union' in any of the module search directories.
// EXPECT-COMPILE-ERROR: Undeclared identifier '__temporary_allocator'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'get_time'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'get_system_time'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'Swap'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'table_find_new'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'bubble_sort'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'running_at_compile_time'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'concatenate'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'uninit'.
// EXPECT-COMPILE-ERROR: The format string requires 2 arguments, but 0 arguments are given.
// Old Jai that no longer compiles on beta 0.2.032 (code from talks, blogs, older books and repos).
// Each snippet builds in its own workspace, so one `jai build.jai` shows every error. The comment
// after each snippet gives the current form and the beta that changed it (from CHANGELOG.txt).
// Old forms that still compile (with a warning or silently, with another meaning) are in 59_ff_old_silent.
// Not testable in a file: `-plug Name` ("Unknown argument '-plug'.", now `+Name`, 0.2.012) and
// `jai f.jai -- args` ("Unknown developer option ...", now `jai f.jai - args`, 0.1.043/0.1.048).

#import "Basic";
#import "Compiler";
#import "Metaprogram_Plugins";

OLD_FORMS :: string.[
    "S :: struct { x: float; #place x; y: float; } main :: () {}",                 // #overlay (x) y: float;          removed 0.2.027
    "S :: struct { a: u32; #overlay a; b: u32; } main :: () {}",                   // #overlay (a) b: u32;            (parentheses required)
    "main :: () { c: Context; }",                                                 // #Context, or Context_Base       removed 0.2.002
    "#import \"Basic\"; V :: struct { a: int; } main :: () { p := New(V, initialized = false); }", // initialize = false  renamed 0.2.032
    "f :: () -> void { return; } main :: () { f(); }",                            // f :: () { ... }  (-> void returns one void value)
    "Base :: struct { a: int; } Derived :: struct { using base: Base; } take :: (b: Base) {} main :: () { d: Derived; take(d); }", // using #as base: Base;  0.1.033
    "S :: struct { a: int; } byval :: (s: S) {} main :: () { s: S; byval(*s); }",  // byval(s)                        0.2.019
    "A :: struct { x: int; } B :: struct { x: int; } main :: () { a: A; b: B = xx a; }", // cast,force(B) a / xx,force a
    "E :: enum u8 { A; B; } main :: () { x := cast(E.loose) 1; }",                // type_info(E).internal_type       removed 0.2.022
    "#import \"Basic\"; main :: () { s := copy_string(\"abc\", allocator = temp); }", // copy_string(\"abc\",, temp)    0.1.080
    "#import \"Math\"; main :: () { v := make_vector2(1, 2); }",                   // Vector2.{1, 2} / {1, 2}          removed 0.2.002
    "lib :: #foreign_library \"libc\"; main :: () {}",                            // #library \"x\"                  removed 0.2.002
    "lib :: #foreign_system_library \"libc\"; main :: () {}",                     // #library,system \"libc\"
    "#run_and_insert \"main :: () {}\";",                                         // #insert #run f() / #insert -> string {}
    "main :: () { x: s64 = 1; v: *void = *x; y := cast(*s64).* v; }",             // (cast(*s64) v).*                 removed 0.2.022
    "main :: () { x := #ifx true then 1; else 2; }",                              // #ifx c then a else b            0.1.084
    "main :: () { y := K; K :: 5; }",                                             // declare local constants first   0.1.065
    "Thing :: struct { a: int; } main :: () { t := *Thing.{1}; }",                // v := Thing.{1}; p := *v;
    "S :: struct { a: int; } main :: () { p: *S; x := p.?a; }",                   // if p  x = p.a;                  removed 0.2.009
    "#import \"Tagged_Union\"; main :: () {}",                                    // union kind: Enum { .A ,, a: T; } module gone 0.2.025
    "#import \"Basic\"; main :: () { a := __temporary_allocator; }",              // temp                            removed 0.2.029
    "#import \"Basic\"; main :: () { t := get_time(); }",                         // seconds_since_init()            removed 0.2.002
    "#import \"Basic\"; main :: () { t := get_system_time(); }",                  // current_time_consensus(), to_calendar()
    "#import \"Basic\"; main :: () { a, b := 1, 2; Swap(*a, *b); }",              // swap(*a, *b) or a, b = b, a;    removed 0.2.022
    "#import \"Hash_Table\"; main :: () { t: Table(int, int); ok, v := table_find_new(*t, 1); }", // table_find (success first)
    "#import \"Sort\"; main :: () { a := int.[3, 1]; bubble_sort(a, (x, y) => x - y); }", // quick_sort (module Sort)   removed 0.2.022
    "main :: () { b := running_at_compile_time(); }",                             // #compile_time                   removed 0.1.043
    "#import \"String\"; main :: () { s := concatenate(\"a\", \"b\"); }",          // join(\"a\", \"b\")
    "#import \"Hash_Table\"; main :: () { t: Table(int, int); uninit(*t); }",      // deinit(*t)
    "#import \"Basic\"; main :: () { print(\"100%%\\n\"); }",                      // print(\"100\\%\\n\"): %% = two arguments since 0.2.022 (keep LAST)
];

#run {
    set_build_options_dc(.{do_output = false});
    for OLD_FORMS {
        w := compiler_create_workspace(tprint("old form %", it_index));
        options := get_build_options(w);
        options.output_type = .NO_OUTPUT;
        set_build_options(options, w);
        if it_index == OLD_FORMS.count - 1 {
            // The old %% is only caught by the Check plugin. Its error ends this #run (it reports through
            // compiler_report), so this snippet must be the last one or later workspaces would never exist.
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
