// A complete fixed-buffer arena (bump allocator), written from scratch.
// - ALLOCATE: align the cursor (16 bytes here), bump, return null when full (the convention for OOM).
// - RESIZE: grow in place when the block is the last one, else allocate + copy (old_size is given).
// - FREE: ignored (bulk reset instead). IS_THIS_YOURS and CAPS answered.
// - THREAD_START/STOP, CREATE_HEAP/DESTROY_HEAP: not supported (single-threaded arena).
// Use: push it as context.allocator around code that allocates freely, then reset() once.
// EXPECT: tree of 1000 nodes built, depth sum 11373
// EXPECT: arena used 31992 of 65536 bytes, 1000 allocations, 0 frees honored
// EXPECT: is_this_yours(node)=true is_this_yours(heap block)=false
// EXPECT: resize of the last block stayed in place: true
// EXPECT: aligned to 16: true
// EXPECT: out of memory returns null: true
// EXPECT: after reset: used 0
#import "Basic";

Arena :: struct {
    memory: [] u8;
    used: int;
    last: *u8;            // start of the most recent block, for in-place RESIZE
    allocations: int;
}

ARENA_ALIGNMENT :: 16;

arena_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    arena := cast(*Arena) allocator_data;
    if mode == {
      case .ALLOCATE;
        return arena_push(arena, size);

      case .RESIZE;
        if old_memory && old_memory == arena.last {
            // The last block can simply be extended (or shrunk) if it still fits.
            start := cast(*u8) old_memory - arena.memory.data;
            if start + size <= arena.memory.count {
                arena.used = start + size;
                return old_memory;
            }
            return null;
        }
        result := arena_push(arena, size);
        if result && old_memory  memcpy(result, old_memory, min(old_size, size));
        return result;

      case .FREE;
        return null;      // individual frees are no-ops; call arena_reset()

      case .IS_THIS_YOURS;
        p := cast(*u8) old_memory;
        mine := p >= arena.memory.data && p < arena.memory.data + arena.memory.count;
        return cast(*void) cast(s64) mine;

      case .CAPS;
        if old_memory { (cast(*string) old_memory).* = "example fixed-buffer arena"; }
        return cast(*void) (Allocator_Caps.HINT_I_AM_A_FAST_BUMP_ALLOCATOR | .IS_THIS_YOURS | .ACTUALLY_RESIZE);

      case .STARTUP; #through;
      case .SHUTDOWN;
        return null;

      case;   // THREAD_START, THREAD_STOP, CREATE_HEAP, DESTROY_HEAP
        assert(false, "arena: mode % is not supported", mode);
        return null;
    }
}

arena_push :: (arena: *Arena, size: s64) -> *void {
    // Align the ADDRESS, not the offset: the backing buffer itself may be only 8-byte aligned.
    address := cast(u64) (arena.memory.data + arena.used);
    aligned := (address + (ARENA_ALIGNMENT - 1)) & ~cast(u64) (ARENA_ALIGNMENT - 1);
    start := arena.used + cast(s64) (aligned - address);
    if start + size > arena.memory.count return null;
    arena.used = start + size;
    arena.last = arena.memory.data + start;
    arena.allocations += 1;
    return arena.last;
}

arena_reset :: (arena: *Arena) { arena.used = 0; arena.last = null; arena.allocations = 0; }

arena_allocator :: (arena: *Arena) -> Allocator { return .{arena_allocator_proc, arena}; }

// "Library" code that allocates and never frees: perfect for an arena.
Tree :: struct { value: int; left, right: *Tree; }

insert :: (root: **Tree, value: int) {
    if !root.* { root.* = New(Tree); root.*.value = value; return; }
    if value < root.*.value insert(*root.*.left, value); else insert(*root.*.right, value);
}

depth_sum :: (t: *Tree, d := 0) -> int {
    if !t return 0;
    return d + depth_sum(t.left, d + 1) + depth_sum(t.right, d + 1);
}

main :: () {
    backing: [65536] u8 #align 16;        // a 64 KiB buffer on the stack; any memory works
    arena := Arena.{memory = backing};
    root: *Tree;
    {
        push_allocator(arena_allocator(*arena));
        x: u32 = 12345;
        for 1..1000 {
            x = x * 1664525 + 1013904223;          // u32 wraps: overflow checks are off by default
            insert(*root, cast(int) (x >> 8));
            free(null);                             // harmless: FREE is ignored
        }
    }
    print("tree of 1000 nodes built, depth sum %\n", depth_sum(root));
    print("arena used % of % bytes, % allocations, 0 frees honored\n", arena.used, arena.memory.count, arena.allocations);

    a := arena_allocator(*arena);
    heap_block := alloc(8);
    yes := a.proc(.IS_THIS_YOURS, 0, 0, root, a.data) != null;
    no  := a.proc(.IS_THIS_YOURS, 0, 0, heap_block, a.data) != null;
    print("is_this_yours(node)=% is_this_yours(heap block)=%\n", yes, no);
    free(heap_block);

    p := alloc(10,, a);
    q := realloc(p, 100, 10,, a);
    print("resize of the last block stayed in place: %\n", p == q);
    print("aligned to 16: %\n", (cast(u64) alloc(3,, a)) % 16 == 0);
    print("out of memory returns null: %\n", alloc(1_000_000,, a) == null);

    arena_reset(*arena);
    print("after reset: used %\n", arena.used);
}
