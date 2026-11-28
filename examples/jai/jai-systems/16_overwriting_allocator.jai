// modules/Overwriting_Allocator wraps any allocator (default: context.allocator) and fills
// memory with a byte pattern (default 0xcd): fresh, uninitialized allocations and freed blocks.
// Reading freed memory then shows cdcdcdcd... instead of plausible stale values; freeing a block
// twice or with the wrong allocator asserts ("was previously freed!").
// Here the base allocator is a Flat_Pool, whose FREE does nothing, so the pattern stays visible.
// Over a real heap the heap may reuse or wipe freed blocks itself (macOS malloc zeroes them).
// Pitfall: get_capabilities(a) passes NULL as allocator_data, and this allocator asserts on
// null data, so query its CAPS through its proc with its data pointer, as below.
// EXPECT: fresh uninitialized block: cdcdcdcdcdcdcdcd
// EXPECT: New(T) still initializes: {0, 0, 0, 0, 0}
// EXPECT: after free the fields read: cdcdcdcdcdcdcdcd cdcdcdcdcdcdcdcd
// EXPECT: wrapper caps: modules/Overwriting_Allocator
#import "Basic";
#import "Flat_Pool";
#import "Overwriting_Allocator";

Record :: struct { a, b, c, d, e: u64; }

main :: () {
    pool: Flat_Pool;
    base := Allocator.{flat_pool_allocator_proc, *pool};
    debug_alloc := get_overwriting_allocator(base);
    push_allocator(debug_alloc);

    raw := New(Record, initialize = false);
    print("fresh uninitialized block: %\n", formatInt(raw.e, base = 16));

    r := New(Record);
    print("New(T) still initializes: %\n", r.*);

    r.* = .{1, 2, 3, 4, 5};
    free(r);
    print("after free the fields read: % %\n", formatInt(r.a, base = 16), formatInt(r.e, base = 16));   // use-after-free, made visible

    name: string;
    debug_alloc.proc(.CAPS, 0, 0, *name, debug_alloc.data);
    print("wrapper caps: %\n", name);
}
