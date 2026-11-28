// RUN-ARGS: --name Ada --count 3 extra
// EXPECT: program name ends with 27_cmdline_args: true
// EXPECT: 6 arguments: ["--name", "Ada", "--count", "3", "extra"] after the program name
// EXPECT: name=Ada count=3 positional=["extra"]
// EXPECT: Hi Ada! Hi Ada! Hi Ada!
// get_command_line_arguments() (Basic) returns [] string with the program path at index 0.
// It allocates (NewArray + to_string views); free it or ignore it in short programs.
// For real tools see modules/Command_Line (parse_arguments into a struct) — that is jai-modules material.
// Arguments for the COMPILE-TIME side go after a lone `-` on the jai command line (see the toolchain reference).

#import "Basic";
#import "String";

main :: () {
    args := get_command_line_arguments();
    print("program name ends with 27_cmdline_args: %\n", ends_with(args[0], "27_cmdline_args"));

    rest: [] string = args;
    rest.data  += 1;            // a view skipping args[0], no copy
    rest.count -= 1;
    print("% arguments: % after the program name\n", args.count, rest);

    name := "nobody";
    count := 1;
    positional: [..] string;
    i := 0;
    while i < rest.count {
        defer i += 1;
        arg := rest[i];
        if arg == {
            case "--name";
                i += 1;
                name = rest[i];
            case "--count";
                i += 1;
                value, ok := to_integer(rest[i]);
                if ok  count = value;
            case;
                array_add(*positional, arg);
        }
    }
    print("name=% count=% positional=%\n", name, count, positional);

    for 1..count  print("Hi %!%", name, ifx it < count then " " else "\n");
}
