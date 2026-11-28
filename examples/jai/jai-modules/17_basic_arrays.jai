// Dynamic arrays [..]T and the array_* procedures from Basic (Array.jai).
// Arguments that modify the array take a pointer (*xs); read-only ones take the view.
// EXPECT: [5, 3, 8, 1, 42] count=5
// EXPECT: find 8: true at index 2
// EXPECT: insert 99 at 1: [5, 99, 3, 8, 1, 42]
// EXPECT: ordered remove index 0: [99, 3, 8, 1, 42]
// EXPECT: unordered remove value 3: [99, 42, 8, 1]
// EXPECT: add_if_unique 42 added: false
// EXPECT: peek 1, pop 1, now [99, 42, 8]
// EXPECT: view(1, 2) = [42, 8]
// EXPECT: copy [-1, 42, 8] original [99, 42, 8]
// EXPECT: reset keeps memory: count 0, still reserved true
// EXPECT: remove inside for: [0, 1, 16, 9]
// EXPECT: NewArray(3, float) = [0, 0, 0]

#import "Basic";

main :: () {
    xs: [..] int;
    defer array_free(xs);
    array_add(*xs, 5, 3, 8);     // several at once
    array_add(*xs, 1);
    slot := array_add(*xs);      // no value: returns a pointer to a new zeroed element
    slot.* = 42;
    print("% count=%\n", xs, xs.count);

    found, index := array_find(xs, 8);
    print("find 8: % at index %\n", found, index);
    array_insert_at(*xs, 99, 1);
    print("insert 99 at 1: %\n", xs);
    array_ordered_remove_by_index(*xs, 0);
    print("ordered remove index 0: %\n", xs);
    array_unordered_remove_by_value(*xs, 3);   // fills the hole with the last element
    print("unordered remove value 3: %\n", xs);
    added := array_add_if_unique(*xs, 42);
    print("add_if_unique 42 added: %\n", added);
    print("peek %, pop %, now %\n", peek(xs), pop(*xs), xs);
    print("view(1, 2) = %\n", array_view(xs, 1, 2));   // no copy

    copy := array_copy(xs);
    defer array_free(copy);
    copy[0] = -1;
    print("copy % original %\n", copy, xs);

    array_reserve(*xs, 100);
    array_reset_keeping_memory(*xs);
    print("reset keeps memory: count %, still reserved %\n", xs.count, xs.allocated >= 100);

    for i: 0..4  array_add(*xs, i * i);
    for xs  if it == 4  remove it;               // 'remove' is unordered (swaps in the last)
    print("remove inside for: %\n", xs);

    floats := NewArray(3, float);                // a [] float view of new zeroed memory
    defer array_free(floats);
    print("NewArray(3, float) = %\n", floats);
}
