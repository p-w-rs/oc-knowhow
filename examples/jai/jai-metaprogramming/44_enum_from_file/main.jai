// Generating declarations from a data file at compile time: the members of the enum come from
// states.txt (read with #filepath so the path does not depend on the working directory), and the
// build fails if the data breaks an assumption. `#assert #run self_test();` runs ordinary test
// code during compilation: a failing assert there stops the build with a stack trace.
// Editing states.txt changes the program at the next compile, nothing else to update.
// EXPECT: State members: ["IDLE", "WALKING", "RUNNING", "JUMPING"]
// EXPECT: State.RUNNING = 2, highest = 3
// EXPECT: from text "running": RUNNING

#import "Basic";
#import "File";
#import "String";
#import "Reflection";

state_names :: () -> [] string {
    text, ok := read_entire_file(tprint("%states.txt", #filepath));
    assert(ok, "states.txt is missing");
    names: [..] string;
    for line: split(text, "\n") {
        name := trim(line);
        if !name || name[0] == #char "#" continue;
        array_add(*names, to_upper_copy(name));
    }
    return names;
}

enum_body :: () -> string {
    sb: String_Builder;
    for state_names() print_to_builder(*sb, "%;\n", it);
    return builder_to_string(*sb);
}

State :: enum u8 {
    #insert #run enum_body();
}

self_test :: () -> bool {
    names := state_names();
    assert(names.count >= 2, "need at least two states");
    for a, i: names  for b, j: names
        if i != j  assert(a != b, "duplicate state %", a);
    assert(names[0] == "IDLE", "the first state must be IDLE (it is the default value)");
    return true;
}
#assert #run self_test();

main :: () {
    print("State members: %\n", enum_names(State));
    print("State.RUNNING = %, highest = %\n", cast(u8) State.RUNNING, enum_highest_value(State));
    s, ok := enum_name_to_value(State, to_upper_copy("running"));
    print("from text \"running\": %\n", s);
}
