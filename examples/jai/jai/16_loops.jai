// EXPECT: inclusive range: 1 2 3
// EXPECT: reversed range: 3 2 1
// EXPECT: empty range (start > end):
// EXPECT: array: [0]=10 [1]=20 [2]=30
// EXPECT: reversed array: 30 20 10
// EXPECT: named: 0:10 1:20 2:30
// EXPECT: by pointer: [11, 21, 31]
// EXPECT: remove multiples of 3 (unordered): [1, 2, 10, 4, 5, 8, 7]
// EXPECT: labeled: (1,1) (2,1)
// EXPECT: while with defer: n=0 n=1 n=2
// EXPECT: named while condition: 4 2 1
// `for a..b` iterates an inclusive range; `for < a..b` visits the same range backwards (a must be <= b).
// Over arrays you get `it` (the element) and `it_index`; name them with `for value, index: array`.
// `it` is read-only: iterate with `for *` to modify elements (it becomes a pointer).
// `remove it;` (resizable arrays and views) swaps in the last element and revisits the slot.
// `break name` / `continue name` target an outer loop by its iterator name.
// There is no C-style three-part for and no `do ... while`; use `while` plus `defer` for the step.

#import "Basic";

main :: () {
    print("inclusive range:");          for 1..3 print(" %", it);       print("\n");
    print("reversed range:");           for < 1..3 print(" %", it);     print("\n");
    print("empty range (start > end):"); for 3..1 print(" %", it);      print("\n");

    arr := int.[10, 20, 30];
    print("array:");          for arr  print(" [%]=%", it_index, it);  print("\n");
    print("reversed array:"); for < arr print(" %", it);               print("\n");
    print("named:");          for value, index: arr  print(" %:%", index, value); print("\n");

    for * arr  it.* += 1;              // it: *int
    print("by pointer: %\n", arr);

    nums: [..] int;
    for 1..10  array_add(*nums, it);
    for nums  if it % 3 == 0  remove it;
    print("remove multiples of 3 (unordered): %\n", nums);

    print("labeled:");
    for outer: 1..3 {
        for inner: 1..3 {
            if inner == 2  continue outer;
            if outer == 3  break outer;
            print(" (%,%)", outer, inner);
        }
    }
    print("\n");

    print("while with defer:");
    n := 0;
    while n < 3 {
        defer n += 1;                  // runs at the end of every iteration, also on continue
        print(" n=%", n);
    }
    print("\n");

    print("named while condition:");
    x := 8;
    while halving := x > 1 {
        x /= 2;
        if x == 3  continue halving;  // never happens here, shows the syntax
        print(" %", x);
    }
    print("\n");
}
