// modules/rpmalloc: a full Jai port of rpmalloc 1.4.4 (thread caches, heaps); no C library needed.
// Start it once with the STARTUP mode, then use Allocator.{rpmalloc_allocator_proc, null}.
// create_heap(a) returns an Allocator bound to a new heap (CREATE_HEAP mode); destroy_heap frees
// every block of that heap at once (DESTROY_HEAP) - per-level or per-request memory.
// The default allocator differs per platform (see its CAPS name): on x64 a stripped-down rpmalloc
// without thread caches; on arm64 (macOS) a wrapper around C malloc.
// EXPECT: rpmalloc caps: rpmalloc 1.4.4 | MULTIPLE_THREADS | CREATE_HEAP | FREE | ACTUALLY_RESIZE | HINT_I_AM_A_GENERAL_HEAP_ALLOCATOR
// EXPECT: 1000 strings from a private heap, checksum 8893
// EXPECT: heap destroyed in one call
// EXPECT-CONTAINS: default allocator:
#import "Basic";
#import "rpmalloc";

main :: () {
    rpmalloc_allocator_proc(.STARTUP, 0, 0, null, null);
    rp := Allocator.{rpmalloc_allocator_proc, null};
    caps, name := get_capabilities(rp);
    print("rpmalloc caps: % | %\n", name, caps);

    level_heap := create_heap(rp);
    checksum := 0;
    {
        push_allocator(level_heap);
        for 1..1000 {
            s := sprint("enemy %", it);      // never freed individually
            checksum += s.count;
        }
    }
    print("1000 strings from a private heap, checksum %\n", checksum);
    destroy_heap(level_heap);
    print("heap destroyed in one call\n");

    _, default_name := get_capabilities(context.default_allocator);
    print("default allocator: %\n", default_name, to_standard_error = true);   // differs per platform
}
