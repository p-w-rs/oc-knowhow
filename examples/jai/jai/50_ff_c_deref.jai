// EXPECT-COMPILE-ERROR: Mismatching levels of indirection. Type wanted: s64; type given: **s64
// EXPECT-COMPILE-ERROR: Automatic dereferencing only travels one layer
// C habit: `*p` to read through a pointer. In Jai a prefix `*` always means "address of", so `*p`
// is a **int here. Dereference with postfix `p.*` (or prefix `(.*) p`).

#import "Basic";

main :: () {
    x := 5;
    p := *x;            // fine: p is *int, the address of x
    y := *p;            // C reading: the value 5. Jai reading: the address of p (**int)
    z: int = y;         // so this fails to type-check
    print("%\n", z);
    // Jai:  z := p.*;   or   z := (.*) p;
}
