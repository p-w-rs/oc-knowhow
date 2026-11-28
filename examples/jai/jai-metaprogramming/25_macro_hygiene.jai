// Macros are hygienic: a macro cannot see the caller's locals unless it backticks them, and the
// caller cannot see the macro's locals unless the macro declares them with a backtick.
// This macro forgot the backtick (`total += amount;` is the fix).
// EXPECT-COMPILE-ERROR: Undeclared identifier 'total'.
// EXPECT-COMPILE-ERROR: While expanding macro 'add_to_total' here...

#import "Basic";

add_to_total :: (amount: int) #expand {
    total += amount;
}

main :: () {
    total := 0;
    add_to_total(5);
    print("%\n", total);
}
