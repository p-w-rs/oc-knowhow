// EXPECT: new: count 0 allocated 0, 40 bytes
// EXPECT: after adds [3, 1, 4, 1, 5] count 5
// EXPECT: find 4: true at index 2
// EXPECT: insert_at 0 -> [9, 3, 1, 4, 1, 5]
// EXPECT: ordered remove -> [3, 1, 4, 1, 5]
// EXPECT: unordered remove of index 0 -> [5, 1, 4, 1]
// EXPECT: pop 1 -> [5, 1, 4]
// EXPECT: growth moved the elements: true
// EXPECT: temp array: [1, 2, 3]
// EXPECT: after array_reset: count 0 allocated 0
// `[..] T` grows through its own allocator (taken from context.allocator at first growth unless you set it).
// The procedures live in Basic (modules/Basic/Array.jai): array_add, array_find, array_insert_at,
// array_ordered_remove_by_index, array_unordered_remove_by_index, pop, array_reserve, array_reset ...
// Every growth may move the elements: pointers and views into the array go stale after array_add.

#import "Basic";

main :: () {
    numbers: [..] int;
    print("new: count % allocated %, % bytes\n", numbers.count, numbers.allocated, size_of(type_of(numbers)));

    array_add(*numbers, 3);              // always pass the array's address
    array_add(*numbers, 1, 4, 1, 5);     // varargs overload adds several
    print("after adds % count %\n", numbers, numbers.count);

    found, index := array_find(numbers, 4);
    print("find 4: % at index %\n", found, index);

    array_insert_at(*numbers, 9, 0);
    print("insert_at 0 -> %\n", numbers);
    array_ordered_remove_by_index(*numbers, 0);
    print("ordered remove -> %\n", numbers);
    array_unordered_remove_by_index(*numbers, 0);    // moves the last element into the hole: O(1)
    print("unordered remove of index 0 -> %\n", numbers);
    last := pop(*numbers);
    print("pop % -> %\n", last, numbers);

    before := numbers.data;
    for 1..100  array_add(*numbers, it);
    print("growth moved the elements: %\n", before != numbers.data);

    scratch: [..] int;
    scratch.allocator = temp;            // grow in temporary storage; nothing to free individually
    array_add(*scratch, 1, 2, 3);
    print("temp array: %\n", scratch);
    reset_temporary_storage();

    array_reset(*numbers);               // frees the memory
    print("after array_reset: count % allocated %\n", numbers.count, numbers.allocated);
}
