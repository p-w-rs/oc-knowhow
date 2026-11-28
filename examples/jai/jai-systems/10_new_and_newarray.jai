// New / NewArray / alloc / free / realloc and friends (modules/Basic).
// - New(T) allocates size_of(T) from context.allocator and runs T's initializer (or zeroes).
//   New(T, initialize=false) skips that (0.2.032 renamed the parameter from 'initialized').
// - NewArray(count, T) returns ([] T, unaligned_base); with alignment=N free unaligned_base, not .data.
// - free(p) frees with context.allocator: free with the SAME allocator you allocated with
//   (free(p,, a) or array_free / array_reset, which use the [..]'s remembered allocator).
// - realloc(memory, new_size, old_size): Jai allocators need the old size.
// - alloc_string / copy_string / sprint allocate; tprint and talloc use temporary storage.
// EXPECT: New(Config): {"untitled", 640, 480}
// EXPECT: NewArray(5, int): [0, 0, 0, 0, 0]
// EXPECT: NewArray with alignment 64: aligned=true, free the base pointer
// EXPECT: realloc kept the data: [1, 2, 3, 4]
// EXPECT: array_reserve: count=0 allocated=100
// EXPECT: array_reset: count=0 allocated=0 data=null
// EXPECT: copy_string owns its bytes: "hello" (original unchanged: "hello")
#import "Basic";

Config :: struct {
    name := "untitled";
    width := 640;
    height := 480;
}

main :: () {
    c := New(Config);
    print("New(Config): %\n", c.*);
    free(c);

    xs := NewArray(5, int);
    print("NewArray(5, int): %\n", xs);
    array_free(xs);                       // same as free(xs.data)

    ys, base := NewArray(16, float, alignment = 64);
    print("NewArray with alignment 64: aligned=%, free the base pointer\n", (cast(u64) ys.data) % 64 == 0);
    free(base);

    p := cast(*int) alloc(3 * size_of(int));
    p[0], p[1], p[2] = 1, 2, 3;
    p = cast(*int) realloc(p, 4 * size_of(int), 3 * size_of(int));
    p[3] = 4;
    view: [] int;
    view.data, view.count = p, 4;
    print("realloc kept the data: %\n", view);
    free(p);

    d: [..] int;
    array_reserve(*d, 100);               // one allocation up front instead of growth steps
    print("array_reserve: count=% allocated=%\n", d.count, d.allocated);
    array_reset(*d);                      // frees and zeroes; array_reset_keeping_memory only sets count = 0
    print("array_reset: count=% allocated=% data=%\n", d.count, d.allocated, ifx d.data then "set" else "null");

    original := "hello";
    owned := copy_string(original);
    owned.data[0] = #char "h";            // writable heap copy (string literals live in read-only memory)
    print("copy_string owns its bytes: \"%\" (original unchanged: \"%\")\n", owned, original);
    free(owned);
}
