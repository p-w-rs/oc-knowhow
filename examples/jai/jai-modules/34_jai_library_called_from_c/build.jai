// Jai as a library for a C program:
//   1. build stats.jai as a STATIC_LIBRARY workspace (stats.a),
//   2. generate stats.h with modules/generate_c_header while that workspace compiles
//      (it collects the #program_export procedures and the types they use),
//   3. compile host.c against both with BuildCpp, producing ./host.
// Checked on macOS arm64 (Apple clang) and Linux x64 (gcc 15 and 16), 0.2.032:
//   - the header declares 'typedef s8 bool', which C23 compilers reject: use -std=c17;
//   - on Linux the Jai objects are not position-independent: link the host with -no-pie;
//   - on macOS pass -mmacosx-version-min to match Jai's target (avoids an ld warning).
// EXE: host
// EXPECT-COMPILE: generated stats.h
// EXPECT: C got: add=42 count=3 mean=3.00
// EXPECT: C got: hello, C, from Jai

#import "Basic";
#import "Compiler";
#import "BuildCpp";
Header :: #import "generate_c_header";

#run {
    set_build_options_dc(.{do_output = false});

    w := compiler_create_workspace("jai library");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_type = .STATIC_LIBRARY;          // -> stats.a (stats.lib on Windows)
    options.output_executable_name = "stats";
    set_build_options(options, w);

    info: Header.Header_Info;
    compiler_begin_intercept(w);
    add_build_file("stats.jai", w);
    failed := false;
    while true {
        message := compiler_wait_for_message();
        Header.handle_message(*info, message);      // collects #program_export declarations
        if message.kind == .COMPLETE {
            failed = (cast(*Message_Complete) message).error_code != .NONE;
            break;
        }
    }
    compiler_end_intercept(w);
    if failed || !Header.generate_header(*info, "stats.h") {
        compiler_set_workspace_status(.FAILED);
        return;
    }
    print("generated stats.h\n");

    flags: [..] string;
    array_add(*flags, "-std=c17");
    #if OS == .MACOS {
        v := get_build_options().minimum_os_version;
        array_add(*flags, tprint("-mmacosx-version-min=%.%", v.major, v.minor));
    } else {
        array_add(*flags, "-no-pie");
    }
    if !build_cpp_executable("host", "host.c", extra = flags, library_files = .["stats.a"], compiler_executable_path = "cc") {
        compiler_set_workspace_status(.FAILED);
    }
}
