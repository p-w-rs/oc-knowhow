// Macros: a procedure marked #expand is pasted into the caller (always inlined, type checked).
// Names inside are hygienic (private) unless backticked:
//   `name := ...     declare in the caller's scope        `name += 1     use a caller variable
//   `defer stmt      run stmt when the CALLER's block ends `return v      return from the CALLER
// Arguments are evaluated once, like a procedure call. Code arguments are pasted with #insert.
// EXPECT: enter block
// EXPECT:   work inside block, counter = 2
// EXPECT: leave block (counter was 2)
// EXPECT: parse_age("42") = 42
// EXPECT: parse_age("-1") = -1 (early return from inside the macro)
// EXPECT: side effect ran once; twice = 8
// EXPECT: timed() ran the body 3 times

#import "Basic";

make_counter :: () #expand { `counter := 0; }
bump         :: () #expand { `counter += 1; }

scope_trace :: (name: string) #expand {
    print("enter %\n", name);
    `defer print("leave % (counter was %)\n", name, `counter);
}

// Leaves the CALLER with `value` when the check fails: error handling without a nested `if` chain.
return_if :: (failed: bool, value: int) #expand {
    if failed `return value;
}

parse_age :: (text: string) -> int {
    n, ok := string_to_int(text);
    return_if(!ok, -2);
    return_if(n < 0, -1);
    return n;
}

side_effect :: () -> int { print("side effect ran once; "); return 4; }
twice :: (x: int) -> int #expand { return x + x; }

timed :: (times: int, body: Code) #expand {
    for 1..times  #insert body;
}

main :: () {
    make_counter();
    {
        scope_trace("block");
        bump(); bump();
        print("  work inside block, counter = %\n", counter);
    }
    print("parse_age(\"42\") = %\n", parse_age("42"));
    print("parse_age(\"-1\") = % (early return from inside the macro)\n", parse_age("-1"));
    v := twice(side_effect());
    print("twice = %\n", v);
    runs := 0;
    timed(3, #code runs += 1);
    print("timed() ran the body % times\n", runs);
}
#import "String";
