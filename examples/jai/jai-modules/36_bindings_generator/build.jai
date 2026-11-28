// Generating Jai bindings from a C header with modules/Bindings_Generator (it
// ships its own libclang, nothing to install), then using them:
//   1. BuildCpp compiles csrc/shapes.c into lib/shapes.dylib or lib/shapes.so
//      (the generator loads the library to check that every symbol exists),
//   2. generate_bindings writes shapes_bindings.jai: structs, enums (C enum prefixes
//      stripped, old names kept as aliases), #c_call function types, #foreign
//      procedures (strip_prefixes renames them; the C symbol stays in quotes),
//      #elsewhere globals, #define constants, C comments, and a #run block that
//      asserts every struct offset; a packed C struct becomes #align 1 members,
//   3. a second workspace compiles main.jai, which imports that file.
// Pitfall: strip_prefixes also renames types, so a C type 'shapes_kind' would
// become 'kind' and clash with a parameter named 'kind' ("Attempt to use a value
// inside its own declaration") - see the note in csrc/shapes.h.
// Commit the generated file next to a small generate.jai like this one, as the
// bundled modules do (stb_image, freetype, lz4, ...); regenerate on header changes.
// EXE: main
// EXPECT-COMPILE: OK! generated 'shapes_bindings.jai'
// EXPECT: MAX_POINTS = 64, kinds SQUARE=2 CIRCLE=1
// EXPECT: area(.SQUARE, 3) = 9
// EXPECT: total via a Jai callback: 21 (2 callbacks)
// EXPECT: mid = {2, 3}
// EXPECT: packed struct: C says 5 bytes, generated Jai type has 5
// EXPECT: C global calls = 3

#import "Basic";
#import "Compiler";
#import "BuildCpp";
#import "File";
#import "Bindings_Generator";

#run {
    set_build_options_dc(.{do_output = false});
    make_directory_if_it_does_not_exist("lib");
    extra: [..] string;
    #if OS == .MACOS {
        v := get_build_options().minimum_os_version;
        array_add(*extra, tprint("-mmacosx-version-min=%.%", v.major, v.minor));
    } else {
        array_add(*extra, "-Wl,-soname,shapes.so");
    }
    if !build_cpp_dynamic_lib("lib/shapes", "csrc/shapes.c", extra = extra, compiler_executable_path = "cc") {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    options: Generate_Bindings_Options;
    array_add(*options.library_search_paths, "lib");
    array_add(*options.libraries, .{filename = "shapes"});   // -> shapes :: #library "lib/shapes";
    array_add(*options.source_files, "csrc/shapes.h");
    array_add(*options.strip_prefixes, "shapes_");          // shapes_area -> area (C name kept in #foreign)
    if !generate_bindings(options, "shapes_bindings.jai") {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    w := compiler_create_workspace("main");
    build := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *build);
    build.output_executable_name = "main";
    #if OS == .LINUX {
        // The library lives in lib/ and has a SONAME, so the executable records just
        // "shapes.so"; Jai's default RUNPATH is only $ORIGIN, so add $ORIGIN/lib.
        // The link command runs through a shell: keep the single quotes, or
        // $ORIGIN is expanded (to nothing) and the RUNPATH becomes "/lib".
        build.additional_linker_arguments = .["-rpath='$ORIGIN/lib'"];
    }
    // macOS needs nothing: install_name @rpath/lib/shapes.dylib + LC_RPATH @loader_path.
    set_build_options(build, w);
    add_build_file("main.jai", w);
}
