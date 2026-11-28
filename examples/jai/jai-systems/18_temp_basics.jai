// Temporary storage: a per-thread bump allocator in context.temporary_storage, reset by you
// at a point where nothing temporary is alive (end of a frame, request, file, loop iteration).
// - tprint(...)            print into temp memory (sprint uses context.allocator)
// - talloc(n)              n bytes of temp memory (8-byte aligned)
// - New(T,, temp), array.allocator = temp, push_allocator(temp)   temp for anything that allocates
// - free() on temp memory is a no-op; reset_temporary_storage() releases everything at once.
// Returning temp memory from a procedure is fine: it lives until the next reset.
// EXPECT: name: /tmp/frame_0042.dat (in temp: true)
// EXPECT: squares: [1, 4, 9, 16, 25]
// EXPECT: node: {7, "node 7"}
// EXPECT: bytes used before reset: 96
// EXPECT: bytes used after reset: 0
#import "Basic";

frame_file :: (n: int) -> string {
    return tprint("/tmp/frame_%.dat", formatInt(n, minimum_digits = 4));
}

squares :: (n: int) -> [] int {
    result: [..] int;
    result.allocator = temp;            // the [..] grows inside temporary storage
    array_reserve(*result, n);          // one temp allocation instead of several abandoned ones
    for 1..n array_add(*result, it * it);
    return result;
}

Node :: struct { id: int; label: string; }

make_node :: (id: int) -> *Node {
    n := New(Node,, temp);
    n.id = id;
    n.label = tprint("node %", id);
    return n;
}

is_temp :: (p: *void) -> bool { return temporary_allocator_proc(.IS_THIS_YOURS, 0, 0, p, null) != null; }

main :: () {
    name := frame_file(42);
    print("name: % (in temp: %)\n", name, is_temp(name.data));
    print("squares: %\n", squares(5));
    print("node: %\n", make_node(7).*);
    print("bytes used before reset: %\n", context.temporary_storage.total_bytes_occupied);
    reset_temporary_storage();          // every string, array and node above is gone now
    print("bytes used after reset: %\n", context.temporary_storage.total_bytes_occupied);
}
