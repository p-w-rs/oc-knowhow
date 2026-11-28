// Generating code from what the program contains. The metaprogram collects every procedure
// tagged @Command while the target compiles, then, when the compiler has typechecked all it can
// (phase TYPECHECKED_ALL_WE_CAN, which waits on the unfilled #placeholder), adds the COMMANDS table
// as a new source string. The compiler resumes and finishes the program.
// - .SKIP_EXPRESSIONS_WITHOUT_NOTES keeps the message stream small: only noted things arrive.
// - Sort what you collected: message order varies between runs, the generated code should not.
// - TYPECHECKED_ALL_WE_CAN can arrive more than once (new code restarts typechecking): generate once.
// - The added text is saved in .build/.added_strings_w3.jai (w3 = the target's workspace number).
// EXE: app
// EXPECT-COMPILE: [build] adding: COMMANDS :: Command.[.{"greet", greet}, .{"quit", quit}, .{"reset", reset}];
// EXPECT: 3 commands registered
// EXPECT: hello!
// EXPECT: state reset
// EXPECT: unknown command 'internal_helper'

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

    compiler_begin_intercept(w, .SKIP_EXPRESSIONS_WITHOUT_NOTES);
    add_build_file("main.jai", w);

    command_names: [..] string;
    generated := false;
    while true {
        message := compiler_wait_for_message();
        if message.kind == {
          case .TYPECHECKED;
            tc := cast(*Message_Typechecked) message;
            for tc.procedure_headers {
                header := it.expression;
                for header.notes if it.text == "Command" array_add(*command_names, copy_string(header.name));
            }

          case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase == .TYPECHECKED_ALL_WE_CAN && !generated {
                generated = true;
                quick_sort(command_names, compare_strings);
                sb: String_Builder;
                append(*sb, "COMMANDS :: Command.[");
                for command_names {
                    if it_index append(*sb, ", ");
                    print_to_builder(*sb, ".{\"%1\", %1}", it);
                }
                append(*sb, "];");
                code := builder_to_string(*sb);
                print("[build] adding: %\n", code);
                add_build_string(code, w);
            }

          case .COMPLETE;
            break;
        }
    }
    compiler_end_intercept(w);
}
