// House rules enforced by the build metaprogram: things the language allows but this project
// forbids. Each violation is reported with compiler_report at the offending node's location, so it
// looks exactly like a compiler error (file:line,col, source excerpt, caret).
// Report modes (0.2.032): .ERROR stops compilation at once (later violations are never reported);
// .ERROR_CONTINUABLE prints and continues, but on its own still exits 0 and writes the executable;
// compiler_set_workspace_status(.FAILED) exits 1 but the executable is also still written.
// So: report each violation as ERROR_CONTINUABLE, then raise one hard .ERROR at
// PRE_WRITE_EXECUTABLE, before anything is written. Exit code 1, no executable.
// EXPECT-COMPILE-ERROR: Error: House rule: struct 'point_2d' must start with a capital letter.
// EXPECT-COMPILE-ERROR: Error: House rule: compare floats with an epsilon, not == or !=.
// EXPECT-COMPILE-ERROR: 2 house-rule violation(s); refusing to write the executable.

#import "Basic";
#import "Compiler";

#run build();

build :: () {
    set_build_options_dc(.{do_output = false});
    w := compiler_create_workspace("Checked App");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = "app";
    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("main.jai", w);

    violations := 0;
    while true {
        message := compiler_wait_for_message();
        if message.kind == {
          case .TYPECHECKED;
            tc := cast(*Message_Typechecked) message;
            violations += check_struct_names(tc);
            violations += check_float_equality(tc);

          case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase == .PRE_WRITE_EXECUTABLE && violations
                compiler_report(tprint("% house-rule violation(s); refusing to write the executable.", violations));

          case .COMPLETE;
            break;
        }
    }
    compiler_end_intercept(w);
}

check_struct_names :: (tc: *Message_Typechecked) -> int {
    found := 0;
    for tc.structs {
        s := it.expression;
        if !in_main_program(s) continue;
        name := s.defined_type.name;
        if name && (name[0] < #char "A" || name[0] > #char "Z") {
            compiler_report(tprint("House rule: struct '%' must start with a capital letter.", name), make_location(s), .ERROR_CONTINUABLE);
            found += 1;
        }
    }
    return found;
}

check_float_equality :: (tc: *Message_Typechecked) -> int {
    found := 0;
    for body: tc.procedure_bodies {
        if !in_main_program(body.expression) continue;
        for body.subexpressions {
            if it.kind != .BINARY_OPERATOR continue;
            op := cast(*Code_Binary_Operator) it;
            if op.operator_type != .IS_EQUAL && op.operator_type != .IS_NOT_EQUAL continue;
            if op.left.type.type != .FLOAT continue;
            compiler_report("House rule: compare floats with an epsilon, not == or !=.", make_location(op), .ERROR_CONTINUABLE);
            found += 1;
        }
    }
    return found;
}

in_main_program :: (node: *Code_Node) -> bool {
    load := node.enclosing_load;
    return load && load.enclosing_import && load.enclosing_import.module_type == .MAIN_PROGRAM;
}
