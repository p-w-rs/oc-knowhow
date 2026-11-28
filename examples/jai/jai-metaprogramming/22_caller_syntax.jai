// Getting the caller's syntax without writing #code yourself:
//   call := #caller_code   (default value of a macro parameter) the Code of the whole call
//   code_of(expr)          the Code of an expression, like type_of but the syntax
//   $args: ..Code          a macro taking any number of unevaluated expressions (as modules/Print_Vars)
// compiler_get_nodes + print_expression (Program_Print) turn them into text at compile time, and
// #insert turns them back into values: a lightweight local "metaprogram" with no build file.
// Note: Code arrives with constants already substituted: `fixed.count` (count of a fixed array)
// and `LIMIT * 2` come back as plain numbers.
// EXPECT-COMPILE: [compile time] code_of gives: clamp_to(a, 0, 10)
// EXPECT: check passed: a + b == 7
// EXPECT: check FAILED: a * b == 13 (line matches: true)
// EXPECT: the call was: check(a * b == 13)
// EXPECT: a = 3
// EXPECT: b * 2 = 8
// EXPECT: names.count = 2
// EXPECT: 3 = 3
// EXPECT: 20 = 20
// EXPECT: the bundled module adds types and alignment:
// EXPECT: a = 3 (s64)

#import "Basic";
#import "Compiler";
#import "Program_Print";
#import "Print_Vars";

source_text :: (code: Code) -> string #compile_time {
    sb: String_Builder;
    print_expression(*sb, compiler_get_nodes(code));
    return builder_to_string(*sb);
}

// The condition's own text becomes the message: no need to repeat it in a string.
check :: (condition: bool, call := #caller_code, loc := #caller_location) #expand {
    CALL_TEXT :: #run source_text(call);
    ARG_TEXT  :: #run -> string {
        root := compiler_get_nodes(call);
        c := cast(*Code_Procedure_Call) root;
        sb: String_Builder;
        print_expression(*sb, c.arguments_unsorted[0].expression);
        return builder_to_string(*sb);
    };
    if condition  print("check passed: %\n", ARG_TEXT);
    else {
        print("check FAILED: % (line matches: %)\n", ARG_TEXT, loc.line_number == `failing_line);
        `last_call = CALL_TEXT;
    }
}

// Each argument is both text (for the label) and code (for the value).
show :: ($args: ..Code) #expand {
    #insert -> string {
        sb: String_Builder;
        for 0..args.count-1
            print_to_builder(*sb, "print(\"% = \%\\n\", #insert args[%]);\n", source_text(args[it]), it);
        return builder_to_string(*sb);
    }
}

clamp_to :: (x: int, lo: int, hi: int) -> int { return ifx x < lo then lo else ifx x > hi then hi else x; }

LIMIT :: 10;

main :: () {
    a := 3; b := 4;
    last_call: string;
    failing_line := 0;
    check(a + b == 7);
    failing_line = #line + 1;
    check(a * b == 13);
    print("the call was: %\n", last_call);

    C :: code_of(clamp_to(a, 0, 10));
    #run print("[compile time] code_of gives: %\n", source_text(C));

    names: [..] string;
    array_add(*names, "ada", "bob");
    fixed := int.[1, 2, 3];
    show(a, b * 2, names.count, fixed.count, LIMIT * 2);
    print("the bundled module adds types and alignment:\n");
    print_vars(a);
}
