// File (open/read/write/seek, whole-file helpers, directories) and File_Utilities
// (visit_files, file_list, file_exists, copy_file). Paths are plain strings with '/'.
// Most procedures return a success bool and log the OS error on failure
// (read_entire_file takes log_errors = false to stay quiet).
// EXPECT: mkdir -p: true
// EXPECT: read 23 bytes: "first line\nsecond line\n"
// EXPECT: exists: true / false; is_directory: true
// EXPECT: listed: scratch/notes/a.txt
// EXPECT: listed: scratch/notes/deep/b.txt
// EXPECT: visited 4 entries (files and directories)
// EXPECT: b.txt says: 12 squared is 144
// EXPECT: path_join: scratch/notes/a.txt
// EXPECT: file_modtime: found=true, after 2020: true
// EXPECT: copy, move, delete: true true true
// EXPECT: absolute path of an existing file ends with a.txt: true
// EXPECT: missing file: success=false
// EXPECT: removed the whole tree: true

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Sort";

main :: () {
    print("mkdir -p: %\n", make_directory_if_it_does_not_exist("scratch/notes/deep", recursive = true));

    write_entire_file("scratch/notes/a.txt", "first line\n");

    // Append: open for writing without truncating, seek to the end.
    file, ok := file_open("scratch/notes/a.txt", for_writing = true, keep_existing_content = true);
    assert(ok);
    file_seek(file, 0, .END);
    file_write(*file, "second line\n");
    file_close(*file);

    // write_entire_file also takes a String_Builder (and resets it).
    b: String_Builder;
    print_to_builder(*b, "% squared is %\n", 12, 144);
    write_entire_file("scratch/notes/deep/b.txt", *b);

    text, read_ok := read_entire_file("scratch/notes/a.txt");
    defer free(text);
    escaped := replace(text, "\n", "\\n");
    print("read % bytes: \"%\"\n", text.count, escaped);

    is_dir := is_directory("scratch/notes");
    print("exists: % / %; is_directory: %\n", file_exists("scratch/notes/a.txt"), file_exists("scratch/none.txt"), is_dir);

    files := file_list("scratch", recursive = true);   // files only, full relative names
    quick_sort(files, compare);                         // directory order is OS-dependent
    for files  print("listed: %\n", it);

    // visit_files calls a procedure per entry with your own user-data pointer.
    entries := 0;
    visit_files("scratch", true, *entries, (info: *File_Visit_Info, counter: *int) {
        counter.* += 1;
    }, visit_directories = true);
    print("visited % entries (files and directories)\n", entries);

    deep := read_entire_file("scratch/notes/deep/b.txt");
    print("b.txt says: %", deep);

    // String.path_join (0.2.018) drops a trailing separator per component;
    // the result is allocated with context.allocator.
    joined := path_join("scratch/", "notes", "a.txt");
    print("path_join: %\n", joined);
    modified, found_time := file_modtime(joined);      // Apollo_Time (File_Utilities, 0.2.025)
    print("file_modtime: found=%, after 2020: %\n", found_time, to_calendar(modified).year > 2020);

    c := copy_file("scratch/notes/a.txt", "scratch/copy.txt");
    m := file_move("scratch/copy.txt", "scratch/moved.txt");
    d := file_delete("scratch/moved.txt");
    print("copy, move, delete: % % %\n", c, m, d);

    // get_absolute_path uses realpath() on Unix: the path must exist.
    absolute, abs_ok := get_absolute_path("scratch/notes/a.txt");
    print("absolute path of an existing file ends with a.txt: %\n", abs_ok && ends_with(absolute, "/scratch/notes/a.txt"));

    _, found := read_entire_file("scratch/nope.txt", log_errors = false);
    print("missing file: success=%\n", found);

    print("removed the whole tree: %\n", delete_directory("scratch") && !file_exists("scratch"));
}
