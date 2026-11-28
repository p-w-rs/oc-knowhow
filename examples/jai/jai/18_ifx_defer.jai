// EXPECT: ifx: big
// EXPECT: ifx block form: computed 9
// EXPECT: ifx without else gives the default value: 0 and "Red"
// EXPECT: ifx without then gives the condition's subject: 7 99
// EXPECT: if-then on one line: then branch
// EXPECT: open resource
// EXPECT: work
// EXPECT: close (deferred, inner)
// EXPECT: close (deferred, outer)
// EXPECT: returned 5 after defer ran
// `ifx cond then a else b` is the expression form of if (no `?:` in Jai). With braces the value is the
// last expression of each block. Without `else` the result is the type's default value.
// `defer stmt;` runs at the end of the enclosing scope, in reverse order of declaration, on every exit path.

#import "Basic";

Car :: struct { color := "Red"; seats := 4; }

counter := 0;
with_defer :: () -> int {
    defer counter += 100;      // runs after the return value has been computed
    counter = 5;
    return counter;
}

main :: () {
    x := 7;
    print("ifx: %\n", ifx x > 5 then "big" else "small");

    y := ifx x > 5 {
        a := x + 2;
        a;                      // value of the block
    } else {
        0;
    }
    print("ifx block form: computed %\n", y);

    car_ptr: *Car;
    z := ifx x > 100 then 1;
    car := ifx car_ptr then car_ptr.*;
    print("ifx without else gives the default value: % and \"%\"\n", z, car.color);

    zero := 0;
    print("ifx without then gives the condition's subject: % %\n", ifx x else 99, ifx zero else 99);

    if x > 5 then print("if-then on one line: then branch\n"); else print("else branch\n");

    {
        print("open resource\n");
        defer print("close (deferred, outer)\n");
        {
            defer print("close (deferred, inner)\n");
            print("work\n");
        }
    }

    result := with_defer();
    print("returned % after defer ran\n", result);
}
