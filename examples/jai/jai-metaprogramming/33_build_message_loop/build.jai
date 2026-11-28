// A build metaprogram: `jai build.jai` runs this file at compile time. It creates a second
// workspace for the real program, intercepts that workspace's message stream and reports what the
// compiler is doing. Messages arrive in a nondeterministic order (compilation is parallel), so it
// collects facts and prints a sorted summary at the end.
// Pitfall: the Check plugin (print-format argument checks etc.) runs only in the workspace the
// default metaprogram creates. Workspaces you create get it only if your loop forwards messages to
// Check.do_error_checking, as below; without that, print("% %", 1) compiles and misbehaves at run time.
// EXE: app
// EXPECT-COMPILE: [build] files of the main program: main.jai, shapes.jai
// EXPECT-COMPILE: [build] module Basic imported: true
// EXPECT-COMPILE: [build] phases (first time seen): ALL_SOURCE_CODE_PARSED -> TYPECHECKED_ALL_WE_CAN -> ALL_TARGET_CODE_BUILT -> PRE_WRITE_EXECUTABLE -> POST_WRITE_EXECUTABLE
// EXPECT-COMPILE: [build] executable written: true, linker exit code 0
// EXPECT-COMPILE: [build] typechecked messages received: true
// EXPECT-COMPILE: [build] compilation finished with error_code NONE
// EXPECT: area of the square: 9

#import "Basic";
#import "Compiler";
#import "String";
#import "Sort";
Check :: #import "Check";

#run build();

build :: () {
    // This workspace (the metaprogram itself) must not produce an executable.
    set_build_options_dc(.{do_output = false});

    w := compiler_create_workspace("Shapes App");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);   // inherit -quiet, backend, checks...
    options.output_executable_name = "app";
    set_build_options(options, w);         // must happen before any source is added

    compiler_begin_intercept(w);           // ask for messages BEFORE adding source
    add_build_file("main.jai", w);         // relative to this file's folder

    files: [..] string;
    phases: [..] string;
    saw_basic := false;
    typechecked_count := 0;
    while true {
        message := compiler_wait_for_message();
        Check.do_error_checking(null, message);    // keep the default checks for this workspace

        if message.kind == {
          case .FILE;
            file := cast(*Message_File) message;
            if file.enclosing_import && file.enclosing_import.module_type == .MAIN_PROGRAM
                array_add(*files, copy_string(path_filename(file.fully_pathed_filename)));

          case .IMPORT;
            import := cast(*Message_Import) message;
            if import.module_name == "Basic" saw_basic = true;

          case .TYPECHECKED;
            typechecked_count += 1;

          case .PHASE;
            phase := cast(*Message_Phase) message;
            array_add_if_unique(*phases, tprint("%", phase.phase));
            if phase.phase == .POST_WRITE_EXECUTABLE
                print("[build] executable written: %, linker exit code %\n", !phase.executable_write_failed, phase.linker_exit_code);

          case .COMPLETE;
            complete := cast(*Message_Complete) message;
            quick_sort(files, compare_strings);
            print("[build] files of the main program: %\n", join(..files, separator = ", "));
            print("[build] module Basic imported: %\n", saw_basic);
            print("[build] phases (first time seen): %\n", join(..phases, separator = " -> "));
            print("[build] typechecked messages received: %\n", typechecked_count > 0);
            print("[build] compilation finished with error_code %\n", complete.error_code);
            break;
        }
    }
    compiler_end_intercept(w);
}
