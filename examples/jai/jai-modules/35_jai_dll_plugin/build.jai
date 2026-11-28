// A Jai program calling a Jai dynamic library. The main program's compile needs
// the finished library (the compiler loads it to resolve symbols), so the build
// waits for the library workspace to complete before adding the program.
// At run time the executable finds plugin.dylib/.so next to itself
// (@loader_path / $ORIGIN rpath).
// EXE: main
// EXPECT: plugin_square(12) = 144
// EXPECT: plugin sees [1 | 2 | 3]

#import "Basic";
#import "Compiler";

#run {
    set_build_options_dc(.{do_output = false});

    lib := compiler_create_workspace("plugin");
    options := get_build_options(lib);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_type = .DYNAMIC_LIBRARY;
    options.output_executable_name = "plugin";
    set_build_options(options, lib);
    compiler_begin_intercept(lib);
    add_build_file("plugin.jai", lib);
    while true {
        message := compiler_wait_for_message();
        if message.kind != .COMPLETE  continue;
        if (cast(*Message_Complete) message).error_code != .NONE {
            compiler_end_intercept(lib);
            compiler_set_workspace_status(.FAILED);
            return;
        }
        break;
    }
    compiler_end_intercept(lib);

    exe := compiler_create_workspace("main");
    options = get_build_options(exe);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = "main";
    set_build_options(options, exe);
    add_build_file("main.jai", exe);
}
