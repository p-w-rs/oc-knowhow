// Build configurations from one metaprogram:
// - Arguments after a lone `-` are ignored by the compiler and handed to the metaprogram as
//   Build_Options.compile_time_command_line:  jai build.jai - release   /  jai build.jai - debug
//   (Old code wrote `jai build.jai -- release`; since 0.1.043 `--` introduces compiler developer
//   options: "Unknown developer option 'release'".) An unknown argument is reported with
//   compiler_report, which fails the build with a pointer into build.jai.
// - Each workspace has its own Build_Options: output_type EXECUTABLE (default), DYNAMIC_LIBRARY,
//   STATIC_LIBRARY, OBJECT_FILE or NO_OUTPUT. The platform extension (.so/.dylib/.dll, .a/.lib,
//   .o/.obj) is appended unless append_executable_filename_extension = false.
//   set_optimization(*options, .DEBUG / .OPTIMIZED / .VERY_OPTIMIZED / ...) sets the related
//   options together (bounds checks, LLVM levels, inlining).
// - Workspaces compile in parallel; one loop can intercept them all (Message.workspace tells them
//   apart, each sends its own COMPLETE).
// - Configuration reaches the program as generated declarations (add_build_string), not macros.
// JAI-ARGS: - release
// EXE: app
// EXPECT-COMPILE: [build] arguments: ["release"]
// EXPECT-COMPILE: [build] wrote app (EXECUTABLE)
// EXPECT-COMPILE: [build] wrote mathlib (DYNAMIC_LIBRARY)
// EXPECT-COMPILE: [build] wrote mathlib_obj (OBJECT_FILE)
// EXPECT-COMPILE: [build] wrote mathlib_static (STATIC_LIBRARY)
// EXPECT: app built as release (bounds checks OFF)

#import "Basic";
#import "Compiler";
#import "String";
#import "Sort";

#run build();

build :: () {
    set_build_options_dc(.{do_output = false});

    args := get_build_options().compile_time_command_line;
    print("[build] arguments: %\n", args);
    release := false;
    for args {
        if it == "release"     release = true;
        else if it == "debug"  release = false;
        else {
            compiler_report(tprint("Unknown build argument '%'. Use: release | debug", it));
            return;
        }
    }

    Product :: struct { name: string; type: Build_Options.Output_Type; file: string; }
    products := Product.[
        .{"app",            .EXECUTABLE,      "main.jai"},
        .{"mathlib",        .DYNAMIC_LIBRARY, "lib.jai"},
        .{"mathlib_static", .STATIC_LIBRARY,  "lib.jai"},
        .{"mathlib_obj",    .OBJECT_FILE,     "lib.jai"},
    ];

    workspaces: [..] Workspace;
    for products {
        w := compiler_create_workspace(it.name);
        options := get_build_options(w);
        copy_commonly_propagated_fields(get_build_options(), *options);
        options.output_type = it.type;
        options.output_executable_name = it.name;
        set_optimization(*options, ifx release then .VERY_OPTIMIZED else .DEBUG);
        if release options.stack_trace = false;
        set_build_options(options, w);
        compiler_begin_intercept(w);
        add_build_file(it.file, w);
        if it.type == .EXECUTABLE {
            add_build_string(tprint("BUILD_KIND :: \"%\"; BOUNDS_CHECKS :: \"%\";",
                                    ifx release then "release" else "debug", options.array_bounds_check), w);
        }
        array_add(*workspaces, w);
    }

    lines: [..] string;
    completed := 0;
    while completed < workspaces.count {
        message := compiler_wait_for_message();
        if message.kind == .PHASE {
            phase := cast(*Message_Phase) message;
            if phase.phase == .POST_WRITE_EXECUTABLE && !phase.executable_write_failed {
                options := get_build_options(message.workspace);
                array_add(*lines, tprint("[build] wrote % (%)", options.output_executable_name, options.output_type));
            }
        }
        if message.kind == .COMPLETE completed += 1;
    }
    for workspaces compiler_end_intercept(it);

    quick_sort(lines, compare_strings);
    for lines print("%\n", it);
}
