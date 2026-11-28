// The two bump-allocating "arenas" that ship with the compiler:
// - Flat_Pool (modules/Flat_Pool.jai): reserves 256 MiB of address space on first use and
//   commits as it grows; get(), reset(), fini(); allocator proc flat_pool_allocator_proc.
//   No setup needed; the preferred choice for new code.
// - Pool (modules/Pool.jai): older; takes 64 KiB blocks from a backing allocator.
//   Call set_allocators(*pool) BEFORE pushing the pool as context.allocator; reset() keeps the
//   blocks for reuse, release() gives them back.
// Both ignore FREE: you free everything at once. The memory debugger does not track them.
// Note the 20256 bytes below: 500 strings need only 4000, the rest are the abandoned old buffers
// of the growing [..] (8, 16, ..., 512 elements of 16 bytes): RESIZE in a bump allocator copies.
// Call array_reserve first when you know the size.
// EXPECT: flat pool: 500 strings, first "item 0", last "item 499"
// EXPECT: flat pool used 20256 bytes, IS_THIS_YOURS=true
// EXPECT: after reset: used 0
// EXPECT: pool: messy result has 10 entries, last = "entry 9"
// EXPECT: pool blocks in use: 1, bytes used > 0: true
// EXPECT: after release: blocks in use 0
#import "Basic";
#import "Flat_Pool";
#import "Pool";

make_names :: (n: int) -> [] string {   // allocates freely from context.allocator
    result: [..] string;
    for 0..n-1 array_add(*result, sprint("item %", it));
    return result;
}

main :: () {
    flat: Flat_Pool;
    names: [] string;
    {
        push_allocator(flat_pool_allocator_proc, *flat);
        names = make_names(500);
    }
    print("flat pool: % strings, first \"%\", last \"%\"\n", names.count, names[0], names[names.count-1]);
    used := flat.current_point - flat.memory_base;
    mine := flat_pool_allocator_proc(.IS_THIS_YOURS, 0, 0, names.data, *flat) != null;
    print("flat pool used % bytes, IS_THIS_YOURS=%\n", used, mine);
    reset(*flat);                           // reset(*flat, overwrite_memory=true) to catch stale pointers
    print("after reset: used %\n", flat.current_point - flat.memory_base);
    fini(*flat);                            // optional at exit: the OS reclaims everything anyway

    pool: Pool;
    set_allocators(*pool);                  // takes blocks from the CURRENT context.allocator
    entries: [] string;
    {
        push_allocator(pool_allocator_proc, *pool);
        list: [..] string;
        for 0..9 array_add(*list, sprint("entry %", it));
        entries = list;
    }
    print("pool: messy result has % entries, last = \"%\"\n", entries.count, entries[entries.count-1]);
    inband, outband := calculate_used_memory(pool);
    blocks := 0;
    b := pool.used_memblocks;
    while b { blocks += 1; b = b.next; }
    print("pool blocks in use: %, bytes used > 0: %\n", blocks, inband > 0);
    release(*pool);
    print("after release: blocks in use %\n", ifx pool.used_memblocks then 1 else 0);
}
