// EXPECT-EXIT: 1
// EXPECT-CONTAINS: checking the invariant
// EXPECT-CONTAINS: Assertion failed: balance must not go negative, got -5
// EXPECT-CONTAINS: Stack trace:
// assert(cond, "format %", args) from Basic: on failure it prints "file:line,col: Assertion failed: message"
// and a stack trace to stderr, then traps; the process exits nonzero (1 on the test machines).
// assert is a macro; `#import "Basic"()(ENABLE_ASSERT=false);` (a program parameter, must be the
// first import of Basic) compiles every assert out, arguments included.
// For a compile-time check use #assert.

#import "Basic";

withdraw :: (balance: int, amount: int) -> int {
    result := balance - amount;
    assert(result >= 0, "balance must not go negative, got %", result);
    return result;
}

main :: () {
    print("checking the invariant\n");
    left := withdraw(10, 3);
    left = withdraw(left, 12);
    print("never printed %\n", left);
}
