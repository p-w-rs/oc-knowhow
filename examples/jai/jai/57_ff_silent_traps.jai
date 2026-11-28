// EXPECT: 1. `for arr it = 0;` leaves [1, 2, 3]; `for * arr it.* = 0;` gives [0, 0, 0]
// EXPECT: 2. ap[0] is the whole [4] s64 [10, 20, 30, 40]; ap.*[1] is 20
// EXPECT: 3. printf letters print literally: 5d xs
// EXPECT: 4. unsigned 0..u-1 with u = 0 ran 4 times before the guard stopped it
// EXPECT: 5. the range end is re-read: 5 6 (start changes are ignored)
// EXPECT: 6. braceless if + '(' needs `then`: 1
// C/Odin habits that COMPILE but do something else than expected (old-Jai habits: 59_ff_old_silent).
// 1. Assigning to `it` for small element types changes a copy (larger types are a compile error).
// 2. `[]` on a pointer is C pointer indexing: on *[4] int, ap[1] would be the memory after the array.
// 3. print has no %d/%s: `%` is the whole placeholder and following letters are text.
// 4. `for 0..n-1` with unsigned n == 0 wraps to a huge range (inclusive ranges + unsigned).
// 5. A variable range end is read every iteration; the start only once.
// 6. `if cond (p).* += 1;` does not parse ("Expected a statement before this semicolon."): the '('
//    continues the condition. Use `if cond then (p).* += 1;` or braces.

#import "Basic";

main :: () {
    arr := int.[1, 2, 3];
    for arr  it = 0;
    first := arr;
    for * arr  it.* = 0;
    print("1. `for arr it = 0;` leaves %; `for * arr it.* = 0;` gives %\n", first, arr);

    values := int.[10, 20, 30, 40];
    ap := *values;
    print("2. ap[0] is the whole % %; ap.*[1] is %\n", type_of(ap[0]), ap[0], ap.*[1]);

    print("3. printf letters print literally: %d %s\n", 5, "x");

    u: u32 = 0;
    runs := 0;
    for 0..u-1 {
        runs += 1;
        if runs == 4  break;            // without this guard: about 4 billion iterations
    }
    print("4. unsigned 0..u-1 with u = 0 ran % times before the guard stopped it\n", runs);

    print("5. the range end is re-read:");
    lo := 5;  hi := 8;
    for lo..hi {
        hi = 6;
        lo = 0;
        print(" %", it);
    }
    print(" (start changes are ignored)\n");

    x := 7;

    n := 0;
    q := *n;
    if x == 7 then (q).* += 1;
    print("6. braceless if + '(' needs `then`: %\n", n);
}
