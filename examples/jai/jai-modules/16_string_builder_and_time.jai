// sprint allocates with context.allocator, tprint uses temporary storage (freed by
// reset_temporary_storage), String_Builder collects pieces without reallocating
// one big string. Apollo_Time is Basic's 128-bit time type (femtoseconds).
// EXPECT: sprint: x=1 (heap) / tprint: y=2 (temporary storage)
// EXPECT: builder length before conversion: 19
// EXPECT: builder: x=5, y=[1, 2] done!
// EXPECT: 2001-09-09T01:46:40.000Z
// EXPECT: 9 September 2001, 01:46:40 (weekday index 0 = Sunday)
// EXPECT: one billion seconds: 1000000000
// EXPECT: slept at least 20 ms: true

#import "Basic";

main :: () {
    s := sprint("x=%", 1);
    defer free(s);
    t := tprint("y=%", 2);
    print("sprint: % (heap) / tprint: % (temporary storage)\n", s, t);

    b: String_Builder;
    append(*b, "x=");
    print_to_builder(*b, "%, y=% ", 5, int.[1, 2]);
    append(*b, "done");
    append(*b, #char "!");
    print("builder length before conversion: %\n", builder_string_length(*b));
    joined := builder_to_string(*b);      // copies out and resets the builder
    defer free(joined);
    print("builder: %\n", joined);

    epoch := APOLLO_TIME_FOR_JAN_1_1970;
    when  := epoch + seconds_to_apollo(1_000_000_000);
    cal   := to_calendar(when, .UTC);
    print("%\n", calendar_to_iso_string(cal));
    print("% (weekday index % = Sunday)\n", calendar_to_string(cal), cal.day_of_week_starting_at_0);
    print("one billion seconds: %\n", to_seconds(when - epoch));

    start := current_time_monotonic();
    sleep_milliseconds(20);
    print("slept at least 20 ms: %\n", to_milliseconds(current_time_monotonic() - start) >= 20);
    reset_temporary_storage();
}
