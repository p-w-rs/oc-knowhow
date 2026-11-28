// Calling a C static library: the build metaprogram compiles csrc/geo.c with
// BuildCpp (the system C compiler: Apple clang on macOS, gcc on Linux, through
// "cc"), then compiles main.jai, which declares the C functions with #foreign.
// The library is static only, so main.jai says #library,no_dll (see there).
// EXE: main
// EXPECT: add: 42
// EXPECT: scale: {6, 8}
// EXPECT: length_sq: 100
// EXPECT: count of 'a' in banana: 3
// EXPECT: sum: 23
// EXPECT:   first callback from C: value 5
// EXPECT: max via callback: 9 (4 callbacks)
// EXPECT: version: geo 1.0
// EXPECT: C global geo_calls: 6
// EXPECT: C layout Record: value@4 port@8 size 12 / Jai: value@4 port@8 size 12
// EXPECT: C layout Packed_Record: value@1 port@5 size 7 / Jai: value@1 port@5 size 7
// EXPECT: #no_padding alone: value@4 port@8 size 10 (only the trailing padding goes)
// EXPECT: record sums: 3007 3007

#import "Basic";
#import "Compiler";
#import "BuildCpp";
#import "File";

#run {
    set_build_options_dc(.{do_output = false});
    make_directory_if_it_does_not_exist("lib");

    extra: [..] string;
    array_add(*extra, "-fPIC");
    #if OS == .MACOS {
        // Match the deployment target Jai links with, or ld warns about a newer object.
        v := get_build_options().minimum_os_version;
        array_add(*extra, tprint("-mmacosx-version-min=%.%", v.major, v.minor));
    }
    // compiler_executable_path: without it BuildCpp uses $CC, then "clang" (absent on some Linux boxes).
    if !build_cpp_static_lib("lib/geo", "csrc/geo.c", extra = extra, compiler_executable_path = "cc") {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    w := compiler_create_workspace("main");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = "main";
    set_build_options(options, w);
    add_build_file("main.jai", w);
}
