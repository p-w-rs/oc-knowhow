// A replacement for modules/Default_Metaprogram.jai, selected with the developer options after `---`:
//     jai main.jai --- import_dir meta meta My_Meta
// The compiler runs THIS file as the first workspace; everything Default_Metaprogram normally does
// is now our job: parse arguments, name the output, choose paths, run plugins/checks (Check is NOT
// loaded here, so print() format checking is gone), and intercept messages.
// Paths given to add_build_file / set_build_options resolve relative to the CALLING file
// (this meta/ folder), so make them absolute from the working directory.
#import "Basic";
#import "Compiler";
#import "String";
#import "Sort";

#run build();

build :: () {
    set_build_options_dc(.{do_output = false, write_added_strings = false});

    args := get_build_options().compile_time_command_line;   // everything before `---`
    w := compiler_create_workspace("My_Meta target");
    options := get_build_options(w);

    files: [..] string;
    for args {
        if it == "-quiet" { options.text_output_flags = 0; continue; }   // no link line, no stats
        if begins_with(it, "-") {
            compiler_report(tprint("My_Meta does not understand '%'", it));
            return;
        }
        array_add(*files, tprint("%/%", get_working_directory(), it));
    }
    if !files { compiler_report("My_Meta: no input files"); return; }

    name, folder := get_basename_and_path(files[0]);
    options.output_executable_name = name;
    options.output_path = folder;
    options.intermediate_path = tprint("%.build", folder);
    set_build_options(options, w);
    print("[My_Meta] building '%' from % file(s)\n", name, files.count);

    compiler_begin_intercept(w);
    for files add_build_file(it, w);

    procedures: [..] string;
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE break;
        if message.kind != .TYPECHECKED continue;
        tc := cast(*Message_Typechecked) message;
        for tc.procedure_headers {
            header := it.expression;
            load := header.enclosing_load;
            if !header.name || !load || !load.enclosing_import || load.enclosing_import.module_type != .MAIN_PROGRAM continue;
            array_add(*procedures, header.name);
        }
    }
    compiler_end_intercept(w);

    quick_sort(procedures, compare_strings);
    print("[My_Meta] main program procedures: %\n", join(..procedures, separator = ", "));
}
