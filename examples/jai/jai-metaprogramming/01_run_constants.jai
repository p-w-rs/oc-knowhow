// #run evaluates code while compiling; the result becomes a constant baked into the program.
// The compile-time print() lines go to the compiler's output, not to the program's.
// EXPECT-COMPILE: [compile time] building the prime table
// EXPECT: FIB_30 = 832040
// EXPECT: PRIMES = [2, 3, 5, 7, 11, 13, 17, 19] (type [8] s64)
// EXPECT: GREETING = built on 8 primes
// EXPECT: is_constant(FIB_30) = true, is_constant(local) = false

#import "Basic";

fib :: (n: int) -> int {
    a, b := 0, 1;
    for 1..n a, b = b, a + b;
    return a;
}

// An expression: any ordinary procedure can run at compile time.
FIB_30 :: #run fib(30);

// The short form `#run -> Type { ... }` runs an anonymous procedure body.
// A dynamic array returned from #run arrives as a fixed-size constant array.
PRIMES :: #run -> [..] int {
    print("[compile time] building the prime table\n");
    result: [..] int;
    n := 2;
    while result.count < 8 {
        is_prime := true;
        for result if n % it == 0 { is_prime = false; break; }
        if is_prime array_add(*result, n);
        n += 1;
    }
    return result;
};

// Strings computed at compile time are fine too (they are copied into the executable).
GREETING :: #run tprint("built on % primes", PRIMES.count);

// Constants from #run can feed other compile-time checks.
#assert FIB_30 == 832040;

main :: () {
    print("FIB_30 = %\n", FIB_30);
    print("PRIMES = % (type %)\n", PRIMES, type_of(PRIMES));
    print("GREETING = %\n", GREETING);
    local := 5;
    print("is_constant(FIB_30) = %, is_constant(local) = %\n", is_constant(FIB_30), is_constant(local));
}
