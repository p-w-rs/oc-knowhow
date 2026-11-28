// Rewriting procedure bodies while the program compiles: when a body arrives in a TYPECHECKED
// message, edit its syntax tree (here: prepend a statement built from Code_* nodes) and hand it
// back with compiler_modify_procedure(). The body is typechecked again and then compiled in its
// modified form. body_flags.ALREADY_MODIFIED marks bodies you have already resubmitted (you will
// see them again), so check it to avoid modifying twice.
// The same approach can add profiling zones, logging or asserts to selected procedures.
// EXE: app
// EXPECT-COMPILE: [build] injected trace into: load_level, save_game
// EXPECT: -> load_level
// EXPECT: -> save_game
// EXPECT:    saving
// EXPECT:    untraced work
// EXPECT: x = 42

#import "Basic";
#import "Compiler";
#import "String";
#import "Sort";

#run build();

build :: () {
    set_build_options_dc(.{do_output = false});
    w := compiler_create_workspace("App");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = "app";
    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("main.jai", w);

    modified: [..] string;
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE break;
        if message.kind != .TYPECHECKED continue;
        tc := cast(*Message_Typechecked) message;
        for tc.procedure_bodies {
            body := it.expression;
            if body.body_flags & .ALREADY_MODIFIED continue;
            if !has_note(body.header, "Trace") continue;

            call := make_call("trace_enter", make_string_literal(body.header.name));
            statements: [..] *Code_Node;
            array_add(*statements, call);
            array_add(*statements, ..body.block.statements);
            body.block.statements = statements;

            compiler_modify_procedure(message.workspace, body);
            array_add(*modified, body.header.name);
        }
    }
    compiler_end_intercept(w);

    quick_sort(modified, compare_strings);
    print("[build] injected trace into: %\n", join(..modified, separator = ", "));
}

has_note :: (header: *Code_Procedure_Header, text: string) -> bool {
    for header.notes if it.text == text return true;
    return false;
}

// Builds the nodes for `name(argument)`; identifiers are resolved when the body is re-checked.
make_call :: (name: string, argument: *Code_Node) -> *Code_Procedure_Call {
    ident := New(Code_Ident);
    ident.kind = .IDENT;
    ident.name = name;

    call := New(Code_Procedure_Call);
    call.kind = .PROCEDURE_CALL;
    call.procedure_expression = ident;
    arguments := NewArray(1, Code_Argument);
    arguments[0].expression = argument;
    call.arguments_unsorted = arguments;
    return call;
}
