// A C shared library (.dylib on macOS, .so on Linux) plus system libraries.
// The build metaprogram compiles csrc/greet.c with BuildCpp into ./libgreet.dylib
// or ./libgreet.so next to the executable, then builds main.jai.
// Where the program finds it at run time (checked, 0.2.032):
//   macOS: BuildCpp sets install_name @rpath/<file>, Jai executables carry
//          LC_RPATH @loader_path, so the library is found next to the executable.
//   Linux: Jai executables carry RUNPATH $ORIGIN. Give the .so a SONAME
//          (-Wl,-soname,...), otherwise its full build path is recorded in NEEDED
//          and the program breaks when moved.
// EXE: main
// EXPECT-COMPILE: called greet_twice(21) at compile time: 42
// EXPECT: run time: greet_twice(5) = 10
// EXPECT: greet_format wrote 12 bytes: hello, world
// EXPECT: strlen("four") = 4
// EXPECT: sqrt(2) from libm = 1.414214
// EXPECT: qsort with a #c_call comparator: [-4, 0, 3, 8, 15]
// EXPECT: C printf: 42 3.50 lit
// EXPECT: after fflush the order is preserved

#import "Basic";
#import "Compiler";
#import "BuildCpp";

#run {
    set_build_options_dc(.{do_output = false});
    extra: [..] string;
    #if OS == .MACOS {
        v := get_build_options().minimum_os_version;
        array_add(*extra, tprint("-mmacosx-version-min=%.%", v.major, v.minor));
    } else {
        array_add(*extra, "-Wl,-soname,libgreet.so");
    }
    if !build_cpp_dynamic_lib("libgreet", "csrc/greet.c", extra = extra, compiler_executable_path = "cc") {
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
