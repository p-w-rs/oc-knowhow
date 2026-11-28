// Text_File_Handler: a small helper for line-based config/data formats. It reads a
// file (start_file) or memory (start_from_memory), checks a "[N]" version line,
// skips blank lines and '#' comments (also at line ends), counts line numbers, and
// error()/warn() log messages that include file and line (to stderr).
// file_to_array / file_to_table are one-call shortcuts.
// EXPECT: format version 2
// EXPECT: line 3: name = Ada Lovelace
// EXPECT: line 4: born = 1815
// EXPECT: line 5: skills = math poetry
// EXPECT: file_to_array: ["a", "b"]
// EXPECT: file_to_table: 2 distinct lines
// EXPECT-CONTAINS: Line 6 of 'people.txt'! missing value for 'bogus'

#import "Basic";
#import "Text_File_Handler";
#import "Hash_Table";

DATA :: #string END
[2]   # the version line must come first
# a comment line
name   Ada Lovelace
born   1815      # trailing comments are stripped
skills math poetry
bogus
END

main :: () {
    handler: Text_File_Handler;
    defer deinit(*handler);
    // start_file(*handler, "people", "people.txt") would read the file instead.
    start_from_memory(*handler, "people", "people.txt", DATA);
    if handler.failed  return;
    print("format version %\n", handler.version);

    for 1..1000 {                                 // bounded: at most 1000 data lines
        line, has_line := consume_next_line(*handler);
        if !has_line  break;
        key, value := break_by_spaces(line);      // first word, rest of the line
        if !value {
            error(handler, "missing value for '%'", key);
            continue;
        }
        print("line %: % = %\n", handler.line_number, key, value);
    }

    ok, lines := file_to_array("inline", use_data_from_memory = true, data_from_memory = "a\n\n  b  \n# c\n");
    print("file_to_array: %\n", lines);
    ok2, distinct := file_to_table("inline", use_data_from_memory = true, data_from_memory = "x\ny\nx\n");
    print("file_to_table: % distinct lines\n", distinct.count);
}
