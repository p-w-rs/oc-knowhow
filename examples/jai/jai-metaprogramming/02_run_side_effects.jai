// #run may have side effects: printing, reading and writing files, calling the Compiler module.
// The compiler's working directory is the folder of the first file, so relative paths resolve there.
// Pitfall: separate #run directives have NO guaranteed order (compilation is a dependency graph,
// not top to bottom). If one #run needs another's side effect, make it depend on a constant the
// other produces, as VERSION_LINE depends on WROTE here.
// EXPECT-COMPILE: [compile time] wrote version.txt: true
// EXPECT-COMPILE: [compile time] #compile_time inside #run = true
// EXPECT: VERSION_LINE = version 3
// EXPECT: read back at run time: version 3
// EXPECT: #compile_time at run time = false

#import "Basic";
#import "File";

write_version :: () -> bool {
    ok := write_entire_file("version.txt", "version 3");
    print("[compile time] wrote version.txt: %\n", ok);
    print("[compile time] #compile_time inside #run = %\n", #compile_time);
    return ok;
}

WROTE :: #run write_version();

// Mentioning WROTE forces the writer to finish first.
// #filepath is the folder of this source file (with a trailing slash): robust for embedding files.
VERSION_LINE :: #run -> string {
    assert(WROTE);
    text, ok := read_entire_file(tprint("%version.txt", #filepath));
    assert(ok, "version.txt should exist");
    return text;
};

main :: () {
    print("VERSION_LINE = %\n", VERSION_LINE);
    text := read_entire_file("version.txt");   // the file really exists on disk
    print("read back at run time: %\n", text);
    print("#compile_time at run time = %\n", #compile_time);
}
