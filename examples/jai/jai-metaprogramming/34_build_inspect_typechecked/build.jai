// Inspecting typechecked code from a metaprogram. TYPECHECKED messages carry fully typed syntax
// trees: procedure headers (with notes and types), bodies (with every subexpression flattened in
// `subexpressions`), structs, declarations. Here we:
//   1. list every procedure of the main program with its type (an "API listing"), and
//   2. emit a compiler WARNING at each call of a procedure tagged @Legacy.
// Warnings print like compiler warnings (file:line,col + excerpt) and do not fail the build.
// EXE: app
// EXPECT-COMPILE: [api] length_squared: procedure (v: Vec2) -> float32
// EXPECT-COMPILE: [api] main: procedure ()
// EXPECT-COMPILE: [api] new_sum: procedure (values: .. s64) -> s64
// EXPECT-COMPILE: [api] old_sum: procedure (a: s64, b: s64) -> s64 @Legacy
// EXPECT-COMPILE: Warning: old_sum() is tagged @Legacy; prefer new_sum().
// EXPECT: 5 9
// EXPECT: 25

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

    listing: [..] string;
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE break;
        if message.kind != .TYPECHECKED continue;

        tc := cast(*Message_Typechecked) message;
        for tc.procedure_headers {
            header := it.expression;
            if !in_main_program(header) continue;
            if header.procedure_flags & (.POLYMORPHIC | .MACRO) continue;
            if !header.name continue;    // anonymous procedures (#run bodies, quick lambdas)
            line := tprint("[api] %: %", header.name, signature(header));
            for header.notes line = tprint("% @%", line, it.text);
            array_add(*listing, line);
        }

        for body: tc.procedure_bodies {
            if !in_main_program(body.expression) continue;
            for body.subexpressions {
                if it.kind != .PROCEDURE_CALL continue;
                call := cast(*Code_Procedure_Call) it;
                callee := call.resolved_procedure_expression;
                if !callee || callee.kind != .PROCEDURE_HEADER continue;
                target := cast(*Code_Procedure_Header) callee;
                for target.notes if it.text == "Legacy"
                    compiler_report(tprint("%() is tagged @Legacy; prefer new_sum().", target.name), make_location(call), .WARNING);
            }
        }
    }
    compiler_end_intercept(w);

    quick_sort(listing, compare_strings);
    for listing print("%\n", it);
}

// type_to_string(header.type) would print "procedure (s64, s64) -> s64" without names;
// the argument declarations carry the names, and their type_inst shows how the type was written.
signature :: (header: *Code_Procedure_Header) -> string {
    sb: String_Builder;
    append(*sb, "procedure (");
    for header.arguments {
        if it_index append(*sb, ", ");
        is_varargs := it.type_inst && (it.type_inst.inst_flags & .VARARGS);
        if is_varargs {
            element := (cast(*Type_Info_Array) it.type).element_type;
            print_to_builder(*sb, "%: .. %", it.name, type_to_string(element));
        } else {
            print_to_builder(*sb, "%: %", it.name, type_to_string(it.type));
        }
    }
    append(*sb, ")");
    for header.returns {
        append(*sb, ifx it_index then ", " else " -> ");
        append(*sb, type_to_string(it.type));
    }
    return builder_to_string(*sb);
}

in_main_program :: (node: *Code_Node) -> bool {
    load := node.enclosing_load;
    return load && load.enclosing_import && load.enclosing_import.module_type == .MAIN_PROGRAM;
}
