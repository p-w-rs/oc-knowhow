// Baking values: `$n: int` makes an argument a compile-time constant inside the body (the caller
// must pass a constant), so #if/#assert can use it. `$$n` bakes only when the caller passes a
// constant; test with is_constant(). #bake_arguments makes a new procedure with some arguments
// fixed (ordinary or `$n` ones); #bake_constants fixes only type variables like `$T`. Using
// #bake_constants on a value parameter fails: "There is no bakeable constant named 'K'. Did you
// mean #bake_arguments?" (see 41_old_forms_fail).
// EXPECT: repeat_char('-', 5) = -----
// EXPECT: scaled(10, constant 4) = 40 (constant path)
// EXPECT: scaled(10, runtime 4) = 40 (runtime path)
// EXPECT: add_100(5) = 105, triple(5) = 15
// EXPECT: show_u8: 200 as u8
// EXPECT: chunk copies: 4 bytes in 1 step, 12 bytes in 2 steps

#import "Basic";

repeat_char :: (c: u8, $n: int) -> string {
    #assert n > 0 "n must be positive";
    buf: [n] u8;                      // n is constant, so a fixed array of size n works
    for 0..n-1 buf[it] = c;
    return copy_string(cast(string) buf);
}

scaled :: (x: int, $$factor: int) -> int, string {
    #if is_constant(factor) {
        #assert factor != 0 "factor 0 would erase everything";
        return x * factor, "constant path";
    } else {
        assert(factor != 0);
        return x * factor, "runtime path";
    }
}

add :: (a: int, b: int) -> int { return a + b; }
add_100 :: #bake_arguments add(b = 100);

scale :: (x: int, $K: int) -> int { return x * K; }
triple :: #bake_arguments scale(K = 3);       // a `$K` VALUE parameter: #bake_arguments, not #bake_constants

show :: (x: $T) { print("show_u8: % as %\n", x, T); }
show_u8 :: #bake_constants show(T = u8);

// A classic use of $: unroll by a constant size.
copy_steps :: ($bytes: int) -> int {
    STEPS :: (bytes + 7) / 8;     // computed at compile time for every distinct `bytes`
    return STEPS;
}

main :: () {
    print("repeat_char('-', 5) = %\n", repeat_char("-", 5));    // a 1-char string converts to u8 (0.2.014)
    r, how := scaled(10, 4);
    print("scaled(10, constant 4) = % (%)\n", r, how);
    f := 4;
    r, how = scaled(10, f);
    print("scaled(10, runtime 4) = % (%)\n", r, how);
    print("add_100(5) = %, triple(5) = %\n", add_100(5), triple(5));
    show_u8(200);
    print("chunk copies: 4 bytes in % step, 12 bytes in % steps\n", copy_steps(4), copy_steps(12));
}
