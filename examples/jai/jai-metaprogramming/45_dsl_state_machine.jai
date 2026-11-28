// A tiny DSL compiled at compile time. The machine is written as text; a compile-time procedure
// parses it, validates it (bad input stops the build at the assert, with the offending line), and
// returns Jai source for two enums and a `step` procedure that #insert pastes at file scope.
// At run time there is no parser and no table lookup left: just a generated switch.
// The generated code can be read in .build/.added_strings_w2.jai.
// EXPECT-COMPILE: [dsl] 3 states, 4 events, 4 transitions
// EXPECT: CLOSED --OPEN--> OPENED
// EXPECT: OPENED --LOCK--> (rejected, stays OPENED)
// EXPECT: OPENED --CLOSE--> CLOSED
// EXPECT: CLOSED --LOCK--> LOCKED
// EXPECT: LOCKED --UNLOCK--> CLOSED

#import "Basic";
#import "String";

DOOR :: #string END
closed -> opened : open
opened -> closed : close
closed -> locked : lock
locked -> closed : unlock
END

compile_machine :: (source: string) -> string {
    states, events: [..] string;
    Transition :: struct { from, to, event: string; }
    transitions: [..] Transition;

    for line: split(source, "\n") {
        l := trim(line);
        if !l continue;
        arrow, colon := find_index_from_left(l, "->"), find_index_from_left(l, ":");
        assert(arrow > 0 && colon > arrow, "[dsl] expected 'from -> to : event', got '%'", l);
        t: Transition;
        t.from  = to_upper_copy(trim(slice(l, 0, arrow)));
        t.to    = to_upper_copy(trim(slice(l, arrow + 2, colon - arrow - 2)));
        t.event = to_upper_copy(trim(slice(l, colon + 1, l.count - colon - 1)));
        for transitions
            assert(!(it.from == t.from && it.event == t.event), "[dsl] two transitions for % on %", t.from, t.event);
        array_add_if_unique(*states, t.from);
        array_add_if_unique(*states, t.to);
        array_add_if_unique(*events, t.event);
        array_add(*transitions, t);
    }
    print("[dsl] % states, % events, % transitions\n", states.count, events.count, transitions.count);

    sb: String_Builder;
    append(*sb, "State :: enum u8 {");
    for states print_to_builder(*sb, " %;", it);
    append(*sb, " }\nEvent :: enum u8 {");
    for events print_to_builder(*sb, " %;", it);
    append(*sb, " }\nstep :: (s: State, e: Event) -> State, bool {\n    if s == {\n");
    for state: states {
        print_to_builder(*sb, "      case .%;\n", state);
        for transitions if it.from == state
            print_to_builder(*sb, "        if e == .% return .%, true;\n", it.event, it.to);
    }
    append(*sb, "    }\n    return s, false;\n}\n");
    return builder_to_string(*sb);
}

#insert #run compile_machine(DOOR);

main :: () {
    s := State.CLOSED;
    for e: Event.[.OPEN, .LOCK, .CLOSE, .LOCK, .UNLOCK] {
        next, ok := step(s, e);
        if ok  print("% --%--> %\n", s, e, next);
        else   print("% --%--> (rejected, stays %)\n", s, e, s);
        s = next;
    }
}
