// Array bounds checks are ON in debug builds (Build_Options.array_bounds_check = .ON) and OFF
// with -o / -od. A failure prints the index, the valid range and the file:line of the subscript,
// then "Panic." and a native stack trace, and exits with code 1. #no_abc on a procedure, block
// or for loop removes the checks locally (example 29 shows #no_aoc, its overflow twin).
// EXPECT-EXIT: 1
// EXPECT-CONTAINS: Array bounds check failed. (The attempted index is 3, but the highest valid index is 2).
// EXPECT-CONTAINS: Panic.
#import "Basic";

last_plus_one :: (values: [] int) -> int {
    return values[values.count];          // off by one
}

main :: () {
    values := int.[10, 20, 30];
    print("%\n", last_plus_one(values));
}
