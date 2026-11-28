// EXPECT-COMPILE-ERROR: Attempt to use a variable from an outer stack frame. (Closures are not supported.)
// JS/Rust/C++-lambda habit: a nested procedure or `x => ...` lambda capturing a local. Jai has no
// closures. Nested procedures may use constants, globals and other procedures from outer scopes, not
// locals: pass the value as a parameter, use a struct, or (inside a macro) a backticked `x.

#import "Basic";

main :: () {
    offset := 10;
    add_offset :: (x: int) -> int { return x + offset; }   // fix: take offset as a parameter
    print("%\n", add_offset(1));
}
