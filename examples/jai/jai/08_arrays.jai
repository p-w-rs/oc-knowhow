// EXPECT: fixed [0, 5, 0, 0] count 4, 32 bytes
// EXPECT: typed literal [1, 2, 3] has type [3] s64
// EXPECT: dot-less literal [4, 5, 6], old dotted form [7, 8]
// EXPECT: sums through [] int: 5 6 30
// EXPECT: a view is count+data (16 bytes): [2, 3]
// EXPECT: grid [[0, 0, 0], [0, 0, 7]]
// EXPECT: nested literal [[1, 2], [3, 4]]
// EXPECT: empty literal: count 0, data is null: true
// Three built-in array kinds:
//   [N] T   fixed: the elements themselves, size known at compile time
//   [] T    view: { count; data } pointing at someone else's elements (what procedures usually take)
//   [..] T  resizable: view + allocated + allocator (see 09_dynamic_arrays.jai)
// Fixed and resizable arrays convert to views implicitly. Literals: T.[a, b], or [a, b] / .[a, b]
// when the type is known from context (the dot-less form arrived in 0.2.031).

#import "Basic";

total :: (xs: [] int) -> int {
    t := 0;
    for xs  t += it;
    return t;
}

main :: () {
    fixed: [4] int;                      // zero-initialized
    fixed[1] = 5;
    print("fixed % count %, % bytes\n", fixed, fixed.count, size_of(type_of(fixed)));

    lit := int.[1, 2, 3];
    print("typed literal % has type %\n", lit, type_of(lit));

    dotless: [] int = [4, 5, 6];
    dotted:  [] int = .[7, 8];
    print("dot-less literal %, old dotted form %\n", dotless, dotted);

    print("sums through [] int: % % %\n", total(fixed), total(lit), total([10, 20]));

    view: [] int = lit;
    view.data  += 1;                     // pointer arithmetic is in elements, not bytes
    view.count -= 1;
    print("a view is count+data (% bytes): %\n", size_of(type_of(view)), view);

    grid: [2][3] int;
    grid[1][2] = 7;
    print("grid %\n", grid);

    nested: [2][2] float = [[1, 2], [3, 4]];
    print("nested literal %\n", nested);

    empty := int.[];
    print("empty literal: count %, data is null: %\n", empty.count, empty.data == null);
}
