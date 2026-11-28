// EXPECT: divmod: 3 r 2; keeping only the first: 3
// EXPECT: hello Ann!
// EXPECT: hello Bob! hello Bob!
// EXPECT: hello Cy?
// EXPECT: varargs: 0 6 9
// EXPECT: named defaults: 1 "def" | 70 "def"
// EXPECT: procedure types: procedure (s64) -> s64
// EXPECT: passing procedures: 42 42 81
// EXPECT: recursion: 3628800
// `name :: (params) -> returns { body }` binds a procedure to a constant.
// Several return values (optionally named, optionally with defaults) are returned with `return a, b;`
// and received with `a, b := f();`; trailing ones may be ignored. Arguments may be named at the call
// site and given in any order. `..T` collects variadic arguments into a [] T; `..array` spreads one.
// Nested procedures are fine but cannot see the enclosing procedure's locals (no closures).

#import "Basic";

divmod :: (a: int, b: int) -> quotient: int, remainder: int {
    return a / b, a % b;
}

greet :: (name: string, punct := "!", times := 1) {
    for 1..times  print("hello %1%2 ", name, punct);
    print("\n");
}

sum :: (values: ..int) -> int {
    total := 0;
    for values  total += it;
    return total;
}

defaults :: (x: int) -> a: int = 1, b: string = "def" {
    if x == 0  return;             // returns the declared defaults
    return x * 10;                 // sets the first, the second keeps its default
}

apply :: (f: (int) -> int, x: int) -> int { return f(x); }
twice :: (x: int) -> int { return x * 2; }
fact  :: (n: int) -> int { if n <= 1 return 1; return n * fact(n - 1); }

main :: () {
    q, r := divmod(17, 5);
    only := divmod(17, 5);
    print("divmod: % r %; keeping only the first: %\n", q, r, only);

    greet("Ann");
    greet("Bob", times = 2);
    greet(punct = "?", name = "Cy");

    print("varargs: % % %\n", sum(), sum(1, 2, 3), sum(..int.[4, 5]));

    a, b := defaults(0);
    c, d := defaults(7);
    print("named defaults: % \"%\" | % \"%\"\n", a, b, c, d);

    print("procedure types: %\n", type_of(twice));
    square :: (x: int) -> int { return x * x; }       // local procedure
    print("passing procedures: % % %\n", apply(twice, 21), apply(x => x + 1, 41), apply(square, 9));
    print("recursion: %\n", fact(10));
}
