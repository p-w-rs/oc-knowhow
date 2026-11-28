// EXPECT: Hello from Jai, 3 + 4 = 7
// EXPECT: type_of(3) is s64
// The smallest useful program: import a module, define `main`, print with `%`.
// `print` comes from module Basic; `%` takes the next argument whatever its type.

#import "Basic";

main :: () {
    a := 3;
    b := 4;
    print("Hello from Jai, % + % = %\n", a, b, a + b);
    print("type_of(3) is %\n", type_of(3));
}
