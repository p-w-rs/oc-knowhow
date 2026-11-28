// Recognizing OLD metaprogramming code. Blog posts, forum snippets and the 2020–23 wiki use names
// that no longer exist. This metaprogram compiles each stale snippet in its own workspace
// (NO_OUTPUT), so one build shows every error (a single file would stop at its first error).
// The current form is next to each case; the errors are what 0.2.032 prints. (The same trick, one
// workspace per snippet, is a cheap way to test that code is rejected.)
//   old                                          current                                    changed
//   #run_and_insert gen();                       #insert #run gen();  /  #insert -> string {}  removed 0.0.021/0.0.061
//   f :: () #body_text { ... }                   #insert -> string { ... } in the body       removed 0.0.015
//   c: Context;                                  c: #Context;  (or Context_Base)             0.1.096 / removed 0.2.002
//   running_at_compile_time()                    #compile_time                              removed 0.1.043
//   compiler_get_command_line_arguments()        get_build_options().compile_time_command_line   removed 0.1.020
//   set_output_executable_name("x")              set_build_options_dc(.{output_executable_name = "x"})  0.1.020
//   compiler_report_error(msg)                   compiler_report(msg, loc, .ERROR)          0.0.039
//   message.kind == .COMPILATION_PHASE           .PHASE  (Message_Phase)                    alias removed 0.2.009
//   Message_Compilation_Phase                    Message_Phase                              0.0.046
//   ...ALL_SOURCE_CODE_THAT_CAN_CURRENTLY_BE_INFERRED_IS_INFERRED   .TYPECHECKED_ALL_WE_CAN 0.0.046
//   .SKIP_DECLARATIONS_WITHOUT_NOTES             .SKIP_EXPRESSIONS_WITHOUT_NOTES            0.0.073
//   .DO_POLYMORPH_REPORT                         .DO_PERFORMANCE_REPORT_POLYMORPHS          0.1.069
//   Build_Options.optimization_level             set_optimization(*options, .OPTIMIZED)     0.1.061
//   Metaprogram_Plugin.handle_one_argument       init(p, options: [] string) -> bool        0.2.012
//   Code_Directive_If / Code_Size_Or_Type_Info   Code_If / Code_Type_Query, Code_Expression_Query  0.1.084 / 0.1.091
//   add_build_string(text)                       add_build_string(text, w)   (-1 = current workspace)
//   #bake_constants f(K = 3) for `$K: int`       #bake_arguments f(K = 3)   (#bake_constants: `$T` only)
//   #import "Tagged_Union"                       union kind: Kind { .A ,, a: T; }           removed 0.2.025
// EXPECT-COMPILE-ERROR: Invalid toplevel directive name 'run_and_insert'
// EXPECT-COMPILE-ERROR: Invalid directive in procedure header.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'Context'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'running_at_compile_time'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'compiler_get_command_line_arguments'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'set_output_executable_name'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'compiler_report_error'.
// EXPECT-COMPILE-ERROR: 'COMPILATION_PHASE' is not a member of
// EXPECT-COMPILE-ERROR: Undeclared identifier 'Message_Compilation_Phase'.
// EXPECT-COMPILE-ERROR: 'ALL_SOURCE_CODE_THAT_CAN_CURRENTLY_BE_INFERRED_IS_INFERRED' is not a member of
// EXPECT-COMPILE-ERROR: 'SKIP_DECLARATIONS_WITHOUT_NOTES' is not a member of Intercept_Flags
// EXPECT-COMPILE-ERROR: 'DO_POLYMORPH_REPORT' is not a member of Intercept_Flags.
// EXPECT-COMPILE-ERROR: 'optimization_level' is not a member of Build_Options.
// EXPECT-COMPILE-ERROR: 'handle_one_argument' is not a member of Metaprogram_Plugin.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'Code_Directive_If'.
// EXPECT-COMPILE-ERROR: Undeclared identifier 'Code_Size_Or_Type_Info'.
// EXPECT-COMPILE-ERROR: Procedure call did not match any of the possible overloads.
// EXPECT-COMPILE-ERROR: There is no bakeable constant named 'K'. Did you mean #bake_arguments?
// EXPECT-COMPILE-ERROR: Unable to find a module called 'Tagged_Union'

#import "Basic";
#import "Compiler";

Stale :: struct { name: string; code: string; }

STALE :: Stale.[
    .{"run_and_insert",   "main :: () { #run_and_insert \"x := 1;\"; }"},
    .{"body_text",        "f :: () #body_text { return \"\"; } main :: () {}"},
    .{"Context",          "main :: () { c: Context; }"},
    .{"running_at_ct",    "main :: () { if running_at_compile_time() {} }"},
    .{"command line",     "#import \"Compiler\"; main :: () { a := compiler_get_command_line_arguments(); }"},
    .{"exe name",         "#import \"Compiler\"; main :: () { set_output_executable_name(\"x\"); }"},
    .{"report_error",     "#import \"Compiler\"; main :: () { compiler_report_error(\"x\"); }"},
    .{"phase alias",      "#import \"Compiler\"; main :: () { m: Message; if m.kind == .COMPILATION_PHASE {} }"},
    .{"phase struct",     "#import \"Compiler\"; main :: () { p: *Message_Compilation_Phase; }"},
    .{"phase name",       "#import \"Compiler\"; main :: () { p: Message_Phase; if p.phase == .ALL_SOURCE_CODE_THAT_CAN_CURRENTLY_BE_INFERRED_IS_INFERRED {} }"},
    .{"intercept flag",   "#import \"Compiler\"; main :: () { f := Intercept_Flags.SKIP_DECLARATIONS_WITHOUT_NOTES; }"},
    .{"polymorph report", "#import \"Compiler\"; main :: () { f := Intercept_Flags.DO_POLYMORPH_REPORT; }"},
    .{"optimization",     "#import \"Compiler\"; main :: () { o: Build_Options; o.optimization_level = 2; }"},
    .{"plugin argument",  "#import \"Compiler\"; main :: () { p: Metaprogram_Plugin; p.handle_one_argument = null; }"},
    .{"static if node",   "#import \"Compiler\"; main :: () { n: *Code_Directive_If; }"},
    .{"query node",       "#import \"Compiler\"; main :: () { n: *Code_Size_Or_Type_Info; }"},
    .{"build string",     "#import \"Compiler\"; main :: () { add_build_string(\"X :: 1;\"); }"},
    .{"bake value",       "scale :: (x: int, $K: int) -> int { return x * K; } triple :: #bake_constants scale(K = 3); main :: () { triple(1); }"},
    .{"tagged union lib", "#import \"Tagged_Union\"; main :: () {}"},
];

#run {
    set_build_options_dc(.{do_output = false});
    for STALE {
        w := compiler_create_workspace(it.name);
        options := get_build_options(w);
        copy_commonly_propagated_fields(get_build_options(), *options);
        options.output_type = .NO_OUTPUT;      // only typecheck; nothing is written
        set_build_options(options, w);
        add_build_string(it.code, w);
    }
}
