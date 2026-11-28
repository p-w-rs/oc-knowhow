// EXPECT-EXIT: 3
// EXPECT: validating input
// EXPECT: error: no input file given (exit code 3)
// `main :: ()` cannot return a value ("Entry point must not return a value"); set the process exit
// code with exit(code) from Basic (an s32). exit() does not run pending `defer`s of the current scope.
// Report errors with log_error (stderr) or print(..., to_standard_error = true).

#import "Basic";

main :: () {
    defer print("this deferred line is skipped by exit()\n");
    print("validating input\n");
    args := get_command_line_arguments();
    if args.count < 2 {
        print("error: no input file given (exit code 3)\n");
        exit(3);
    }
    print("input: %\n", args[1]);
}
