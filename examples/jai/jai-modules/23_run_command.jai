// Process.run_command starts a program with an argument array (no shell parsing,
// so "a b" stays one argument), optionally captures stdout/stderr, and reports how
// it ended. On Unix a bare program name is searched in PATH only, and a relative
// program path is resolved against working_directory.
// (Unix only as written: it runs /bin/sh and printf.)
// EXPECT: EXITED exit=3 stdout=[hello] stderr=[oops]
// EXPECT: kill -9: SIGNALED signal=9 exit code non-zero: true
// EXPECT: missing program: FAILED_TO_LAUNCH
// EXPECT: timeout reached: true, child killed: SIGNALED
// EXPECT: working_directory: [scratch_dir]
// EXPECT: arguments stay separate: [a b|c|]
// EXPECT: split a command line: ["cc", "-o", "my prog", "main.c"]
// EXPECT: create_process + read_from_process: [1 2 3]

#import "Basic";
#import "Process";
#import "String";
#import "File";

main :: () {
    r, out, err := run_command("sh", "-c", "echo hello; echo oops 1>&2; exit 3", capture_and_return_output = true);
    print("% exit=% stdout=[%] stderr=[%]\n", r.type, r.exit_code, trim(out), trim(err));

    killed := run_command("sh", "-c", "kill -9 $$");
    print("kill -9: % signal=% exit code non-zero: %\n", killed.type, killed.signal, killed.exit_code != 0);

    // run_command logs the OS error itself when the program cannot start.
    missing := run_command("no-such-program-for-this-example");
    print("missing program: %\n", missing.type);

    slow, slow_out, _, timed_out := run_command("sh", "-c", "sleep 5; echo late", capture_and_return_output = true, timeout_ms = 200);
    print("timeout reached: %, child killed: %\n", timed_out, slow.type);

    make_directory_if_it_does_not_exist("scratch_dir");
    _, here := run_command("sh", "-c", "basename \"$PWD\"", working_directory = "scratch_dir", capture_and_return_output = true);
    print("working_directory: [%]\n", trim(here));
    delete_directory("scratch_dir");

    _, printed := run_command("printf", "%s|", "a b", "c", capture_and_return_output = true);
    print("arguments stay separate: [%]\n", printed);

    print("split a command line: %\n", break_command_into_strings("cc -o \"my prog\" main.c"));

    // Lower level: start, read output as it arrives, then collect the result.
    process: Process;
    if create_process(*process, "sh", "-c", "for i in 1 2 3; do echo $i; done", capture_and_return_output = true) {
        defer deinit(*process);
        collected: String_Builder;
        buffer: [256] u8;
        while !process.output.eof {
            ok, n_out, n_err := read_from_process(*process, buffer, .[], timeout_ms = 1000);
            if !ok  break;
            append(*collected, buffer.data, n_out);
        }
        _, result := get_process_result(*process);
        lines := split(trim(builder_to_string(*collected)), "\n");
        print("create_process + read_from_process: [%]\n", join(..lines, separator = " "));
    }
}
