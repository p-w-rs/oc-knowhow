// Sizing temporary storage from a build metaprogram:
// - Build_Options.temporary_storage_size: the main thread's first page (default 32768 bytes).
//   It is a static buffer in the executable, so keep it modest (here 1 MiB).
// - Threads get their own: thread_init(..., temporary_storage_size = N) (default 16384) or
//   Thread_Group init(..., temporary_storage_size = N).
// - A metaprogram workspace does not inherit -quiet: set text_output_flags = 0 yourself.
// EXE: big_temp
// EXPECT: main thread temporary storage: 1048576 bytes
// EXPECT: 200 KiB of temp allocations, overflow pages: 0
// EXPECT: worker thread temporary storage: 262144 bytes
#import "Basic";
#import "Compiler";

#run {
    set_build_options_dc(.{do_output = false});     // this file itself produces no program
    w := compiler_create_workspace("big temp");
    options := get_build_options(w);
    options.output_executable_name = "big_temp";
    options.temporary_storage_size = 1024 * 1024;
    options.text_output_flags = 0;
    set_build_options(options, w);
    add_build_file("main.jai", w);
}
