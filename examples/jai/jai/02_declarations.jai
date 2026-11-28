// EXPECT: counter=0 ratio=0 name=""
// EXPECT: inferred: s64 float32 string bool
// EXPECT: LIMIT=10 typed constant=2.5 (float64)
// EXPECT: a=1 b=2 c=3 | swapped b=1 a=2
// EXPECT: three at once: 7 7 7
// EXPECT: uninitialized then set: 42
// Declarations are always `name : type = value`; either the type or the value may be left out.
//   `x: T;`        variable, zero-initialized (numbers 0, strings empty, pointers null)
//   `x := v;`      variable, type inferred from v
//   `X :: v;`      compile-time constant (procedures, structs and enums are declared this way too)
//   `X : T : v;`   typed constant
//   `x: T = ---;`  explicitly uninitialized (you promise to write it before reading it)

#import "Basic";

LIMIT :: 10;              // constants may live at file scope; order of file-scope declarations does not matter
SCALE : float64 : 2.5;

main :: () {
    counter: int;
    ratio: float;
    name: string;
    print("counter=% ratio=% name=\"%\"\n", counter, ratio, name);

    i := 1;  f := 1.0;  s := "text";  ok := true;
    print("inferred: % % % %\n", type_of(i), type_of(f), type_of(s), type_of(ok));
    print("LIMIT=% typed constant=% (%)\n", LIMIT, SCALE, type_of(SCALE));

    a, b, c := 1, 2, 3;            // several declarations in one statement
    print("a=% b=% c=% | ", a, b, c);
    a, b = b, a;                   // multiple assignment evaluates the right side first
    print("swapped b=% a=%\n", b, a);

    x, y, z: int = 7;              // one value on the right is copied to every name
    print("three at once: % % %\n", x, y, z);

    big: [1024] u8 = ---;          // skip zeroing a large buffer you will fill anyway
    big[0] = 42;
    print("uninitialized then set: %\n", big[0]);
}
