// modules/String: splitting, searching, trimming, replacing, case and paths.
// trim/split_from_left return views into the input (no copies). split returns
// views too, but allocates the array of views with context.allocator (since
// 0.1.080; older code assumed temporary storage: write split(s, sep,, temp)).
// join, replace and the *_copy procedures allocate the result.
// Renamed long ago, still seen in old code: to_lower(s) -> to_lower_in_place(s) /
// to_lower_copy(s); index_of_string -> find_index_from_left; concatenate -> join;
// contains() returns (found, remainder) since 0.1.096.
// EXPECT: 5 parts
// EXPECT: [width] = [640]
// EXPECT: [title] = [hello world]
// EXPECT: [on] = [true]
// EXPECT: a, b, c | x/y
// EXPECT: contains: true, found at 1 (from left) and 3 (from right)
// EXPECT: replace: one 2 2 (2 replacements)
// EXPECT: MIXED mixed true true
// EXPECT: path: c.txt | txt | c | /a/b/
// EXPECT: compare: -1 1, equal_nocase: true

#import "Basic";
#import "String";

main :: () {
    line  := "  width = 640; height=480 ; title = hello world ; ratio = 1.5; on = true";
    parts := split(line, ";",, temp);      // separator: a string or a u8; array in temporary storage
    print("% parts\n", parts.count);
    for parts {
        found, key, value := split_from_left(trim(it), #char "=");
        key, value = trim(key), trim(value);   // "ratio " still had a space before the '='
        if key == "height" || key == "ratio"  continue;
        print("[%] = [%]\n", key, value);
    }

    words := string.["x", "y"];
    print("% | %\n", join("a", "b", "c", separator = ", "), join(..words, separator = "/"));
    print("contains: %, found at % (from left) and % (from right)\n",
        contains("haystack", "st"), find_index_from_left("a.b.c", #char "."), find_index_from_right("a.b.c", #char "."));
    replaced, count := replace("one two two", "two", "2");
    print("replace: % (% replacements)\n", replaced, count);
    print("% % % %\n", to_upper_copy("MiXed"), to_lower_copy("MiXed"), begins_with("prefix_x", "prefix"), ends_with("a.jai", ".jai"));
    print("path: % | % | % | %\n", path_filename("/a/b/c.txt"), path_extension("/a/b/c.txt"), path_strip_extension("c.txt"), path_strip_filename("/a/b/c.txt"));
    print("compare: % %, equal_nocase: %\n", compare("a", "b"), compare("b", "a"), equal_nocase("ABC", "abc"));
}
