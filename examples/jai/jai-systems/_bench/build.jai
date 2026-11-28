// Builds the benchmarks into bin/ with the same settings as `jai f.jai -o`
// (VERY_OPTIMIZED: LLVM O3 + vectorizers, bounds/cast/null checks off, stack traces off).
//   jai build.jai                 all of them
//   jai build.jai - c_false_sharing d_alignment     only these
#import "Basic";
#import "Compiler";
#import "File";

BENCHMARKS :: string.["a_locality", "b_aos_soa", "c_false_sharing", "d_alignment", "e_alloc_speed"];

#run {
    set_build_options_dc(.{do_output = false});         // build.jai itself produces nothing
    make_directory_if_it_does_not_exist("bin");         // the linker does not create it
    wanted := get_build_options().compile_time_command_line;
    for name: BENCHMARKS {
        if wanted.count && !array_find(wanted, name) continue;
        w := compiler_create_workspace(name);
        o := get_build_options(w);
        set_optimization(*o, .VERY_OPTIMIZED);
        o.stack_trace = false;
        o.output_executable_name = name;
        o.output_path = "bin/";
        o.text_output_flags = 0;
        if name == "e_alloc_speed" o.temporary_storage_size = 64 * 1024 * 1024;   // temp batches fit without overflow pages
        set_build_options(o, w);
        add_build_file(tprint("%.jai", name), w);
    }
}
