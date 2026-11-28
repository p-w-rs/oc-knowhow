// Command_Line.parse_arguments(T) fills a struct from the program's arguments.
// Each member is a flag "-name" (one dash by default); bools take no value,
// [N]T members take N values, enums take the member name (case-sensitive).
// Notes like @"?text" become -help text. Words without a dash, and everything
// after "--", are returned as free arguments. On any error it prints a message,
// returns ok=false, and leaves the exit code to you.
// RUN-ARGS: -width 800 -name Ada -verbose -size 3 4 -mode FAST input.txt -- -not-a-flag
// EXPECT: argv[0] is included: true (14 strings)
// EXPECT: ok=true
// EXPECT: width=800 name=Ada verbose=true scale=1.5 size=[3, 4] mode=FAST
// EXPECT: explicitly set: width=true scale=false
// EXPECT: free arguments: ["input.txt", "-not-a-flag"]
// EXPECT: parsing a fixed list: ok=false
// EXPECT-CONTAINS: Command-line argument 1 ('bogus') is not valid.

#import "Basic";
#import "Command_Line";
#import "String";

Mode :: enum { FAST; SAFE; }

Options :: struct {
    width   := 640;     @"?Window width in pixels."
    name    := "anon";  @"?Your name."
    verbose := false;   @"?Print more."
    scale   := 1.5;
    size:   [2] int;    @"?Two numbers."
    mode    := Mode.SAFE;
}

main :: () {
    raw := get_command_line_arguments();
    print("argv[0] is included: % (% strings)\n", ends_with(raw[0], "22_command_line"), raw.count);

    ok, opts, is_set, free_args := parse_arguments(Options);
    print("ok=%\n", ok);
    print("width=% name=% verbose=% scale=% size=% mode=%\n", opts.width, opts.name, opts.verbose, opts.scale, opts.size, opts.mode);
    print("explicitly set: width=% scale=%\n", is_set.width, is_set.scale);   // Is_Set(Options) has one bool per member
    print("free arguments: %\n", free_args);

    // The args parameter parses any list; it must start with a program name.
    bad_ok := parse_arguments(Options, args = .["prog", "-bogus", "1"]);
    print("parsing a fixed list: ok=%\n", bad_ok);
    if !ok  exit(1);
}
