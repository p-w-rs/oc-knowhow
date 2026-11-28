// context.logger / context.logger_data decide where log(), log_error() and module messages go.
// A Logger is (message: string, data: *void, info: Log_Info). Swap it for one call tree to capture,
// filter or redirect messages; the default logger writes to stdout (stderr for .ERROR).
// EXPECT: captured 3 lines, 1 error:
// EXPECT:   [info] loading level 4
// EXPECT:   [ERROR] missing texture 'rock.png'
// EXPECT:   [info] done
// EXPECT: back to the default logger
#import "Basic";

Capture :: struct {
    lines: [..] string;
    errors: int;
}

capture_logger :: (message: string, data: *void, info: Log_Info) {
    cap := cast(*Capture) data;
    is_error := (info.common_flags & .ERROR) != 0;
    if is_error cap.errors += 1;
    // The message lives in temporary storage: copy it if it must outlive the frame.
    text := message;
    if text && text[text.count-1] == #char "\n" text.count -= 1;
    array_add(*cap.lines, sprint("[%] %", ifx is_error then "ERROR" else "info", text));
}

load_level :: (n: int) {           // pretend this is library code that just logs
    log("loading level %", n);
    log_error("missing texture '%'", "rock.png");
    log("done");
}

main :: () {
    cap: Capture;
    {
        old_logger, old_data := context.logger, context.logger_data;
        context.logger, context.logger_data = capture_logger, *cap;
        defer context.logger, context.logger_data = old_logger, old_data;
        load_level(4);
    }
    print("captured % lines, % error:\n", cap.lines.count, cap.errors);
    for cap.lines print("  %\n", it);
    log("back to the default logger");
}
