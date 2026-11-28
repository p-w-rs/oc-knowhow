// assert(cond, format, args..) is a macro in Basic: on failure it formats the message with tprint
// and calls context.assertion_failed(loc, message) -> bool; true means "break" (debug_break, which
// ends the program when no debugger is attached), false means continue.
// Part 1 installs a collecting handler for one call tree (a test runner pattern).
// Part 2 uses the default handler: "path:line,col: Assertion failed: <message>" plus the Jai stack
// trace on stderr, exit code 1. The stack trace needs stack_trace = true (not with -o, which still
// keeps the assert itself). Only #import "Basic"()(ENABLE_ASSERT=false) removes asserts, and then the
// condition is not evaluated at all: never put side effects inside assert().
// EXPECT-EXIT: 1
// EXPECT: check 1 failed at line 31: expected 4, got 5
// EXPECT: check 2 failed at line 32: name must not be empty
// EXPECT: 2 of 3 checks failed, program continued
// EXPECT-CONTAINS: Assertion failed: balance went negative: -20
// EXPECT-CONTAINS: Stack trace:
// EXPECT-CONTAINS: withdraw
#import "Basic";

failures := 0;

collecting_handler :: (loc: Source_Code_Location, message: string) -> bool {
    failures += 1;
    print("check % failed at line %: %\n", failures, loc.line_number, message);
    return false;                 // do not break: keep running
}

Account :: struct { balance: int; }

run_checks :: () {
    value := 2 + 3;
    name := "";
    assert(value == 4, "expected %, got %", 4, value);
    assert(name.count > 0, "name must not be empty");
    assert(value > 0, "this one passes");
}

withdraw :: (a: *Account, amount: int) {
    a.balance -= amount;
    assert(a.balance >= 0, "balance went negative: %", a.balance);
}

main :: () {
    push_context .{assertion_failed = collecting_handler} {
        run_checks();
    }
    print("% of 3 checks failed, program continued\n", failures);

    account := Account.{balance = 30};
    withdraw(*account, 50);       // default handler: report, then stop with exit code 1
    print("not reached\n");
}
