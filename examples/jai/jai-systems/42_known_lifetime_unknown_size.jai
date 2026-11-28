// Situation 2 of 4: you know HOW LONG the memory lives (until this request, file, level or frame
// is done) but not HOW MUCH you will need. Everything grows until a known end point, then all
// of it dies at once. Answer: an arena that grows in pieces and is reset or released in one call.
// - Chunk_Arena below (ours): bump allocation inside fixed-size chunks taken from a backing heap;
//   a full chunk is left behind and a new one is linked in (a request bigger than a chunk gets a
//   chunk of its own). Existing allocations NEVER move, so pointers into the arena stay valid
//   until the reset. reset() keeps the first chunk for the next round, release() frees them all.
//   FREE is ignored; RESIZE grows in place only for the most recent block.
// - Contrast: elements stored INSIDE a [..] move whenever it has to grow (RESIZE = new block +
//   copy). A pointer taken before the growth then reads a stale copy. The [..] lives in a
//   Flat_Pool here because a bump allocator never reuses the old block, which keeps the stale
//   read deterministic; with a general heap the old block is freed and may hold anything.
// - The usual fix keeps both: allocate the objects from the arena (stable) and keep a growing
//   [..] of POINTERS to them as the index (the index moves, the objects don't).
// - Shipped answers for this situation: Flat_Pool (one range of address space reserved up front,
//   256 MiB by default, so it never needs chunks; reset() is O(1)) and temp with
//   reset_temporary_storage() (its overflow pages are chunks too). Both keep addresses stable
//   until their reset, and both align to 8 bytes, so entries pack tighter than in our arena.
// - A heap per lifetime (rpmalloc module) also works, with a trap: destroy_heap does NOT free
//   the heap's blocks in 0.2.032. DESTROY_HEAP only parks the heap for reuse (like C rpmalloc's
//   heap_release), and the next create_heap hands back the same heap with the old blocks still
//   allocated, so a loop of create/allocate/destroy grows forever. Call the module's
//   heap_free_all first. (The x64 default allocator behaves the same; on arm64 macOS it has no
//   heaps at all.)
// EXPECT: request 1: 300 entries 48 bytes apart in 4 chunks of 4096 bytes; the 10000-byte buffer got its own chunk
// EXPECT: pointer kept from the start sees an update made through the index: 1000 (same object)
// EXPECT: reset: 1 chunk kept, 4 freed; request 2 (200 entries) made 2 new heap calls
// EXPECT: release: heap calls 7, frees 7
// EXPECT: [..] Entry: elements moved 6 times while growing to 300
// EXPECT: pointer kept from the start reads 0 after an update to 1000: stale copy
// EXPECT: Flat_Pool: 300 entries 40 bytes apart, 11999 bytes in one reserved range, sum 44850
// EXPECT: temp: 300 entries 40 bytes apart, 12000 bytes (sizes padded to 8), sum 44850
// EXPECT: rpmalloc, 3 rounds of create_heap + 100 bytes + destroy_heap: same heap each time: true, it still owns 3 of the 3 blocks
// EXPECT: heap_free_all, then destroy_heap: the heap owns 0 of them, the next create_heap starts empty: true
#import "Basic";
#import "Flat_Pool";
rp :: #import "rpmalloc";

Chunk :: struct {
    next: *Chunk;
    size: int;              // usable bytes after this header
}

Chunk_Arena :: struct {
    chunk_size := 4096;
    backing:  Allocator;    // where chunks come from; unset = context.allocator at first use
    first, current: *Chunk;
    used:     int;          // bytes used in 'current'
    last:     *u8;          // most recent block, the only one RESIZE may grow in place
    chunks:   int;
}

ARENA_ALIGN :: 16;

payload :: (c: *Chunk) -> *u8 { return cast(*u8) (c + 1); }

arena_get :: (a: *Chunk_Arena, size: int) -> *void {
    if a.current {
        // Align the address, not the offset (the backing block may be less aligned than we want).
        base  := payload(a.current);
        at    := cast(*u8) ((cast(int) (base + a.used) + ARENA_ALIGN - 1) & ~(ARENA_ALIGN - 1));
        start := at - base;
        if start + size <= a.current.size {
            a.used = start + size;
            a.last = at;
            return at;
        }
    }
    if !a.backing.proc  a.backing = context.allocator;
    usable := max(a.chunk_size, size + ARENA_ALIGN);
    c := cast(*Chunk) a.backing.proc(.ALLOCATE, size_of(Chunk) + usable, 0, null, a.backing.data);
    if !c  return null;
    c.next, c.size = null, usable;
    if a.current  a.current.next = c;  else a.first = c;
    a.current = c;
    a.chunks += 1;
    a.used = 0;
    return arena_get(a, size);          // fits now
}

arena_reset :: (a: *Chunk_Arena) {     // end of one lifetime: keep the first chunk for the next
    if !a.first  return;
    c := a.first.next;
    while c { next := c.next; a.backing.proc(.FREE, 0, 0, c, a.backing.data); a.chunks -= 1; c = next; }
    a.first.next = null;
    a.current, a.used, a.last = a.first, 0, null;
}

arena_release :: (a: *Chunk_Arena) {   // give everything back
    arena_reset(a);
    if a.first  a.backing.proc(.FREE, 0, 0, a.first, a.backing.data);
    a.first, a.current, a.chunks = null, null, 0;
}

chunk_arena_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    a := cast(*Chunk_Arena) data;
    if mode == {
      case .ALLOCATE;
        return arena_get(a, size);
      case .RESIZE;
        if old_memory && old_memory == a.last {
            start := cast(*u8) old_memory - payload(a.current);
            if start + size <= a.current.size { a.used = start + size; return old_memory; }
        }
        result := arena_get(a, size);
        if result && old_memory  memcpy(result, old_memory, min(old_size, size));
        return result;
      case .FREE;
        return null;                    // freed in bulk by arena_reset / arena_release
      case .IS_THIS_YOURS;
        c := a.first;
        while c {
            if old_memory >= payload(c) && old_memory < payload(c) + c.size  return cast(*void) 1;
            c = c.next;
        }
        return null;
      case .CAPS;
        if old_memory { (cast(*string) old_memory).* = "example chunk arena"; }
        return cast(*void) (Allocator_Caps.HINT_I_AM_A_FAST_BUMP_ALLOCATOR | .ACTUALLY_RESIZE | .IS_THIS_YOURS);
      case .STARTUP; #through;
      case .SHUTDOWN;
        return null;
      case;
        assert(false, "chunk arena: mode % is not supported", mode);
        return null;
    }
}

// The work: entries allocated one by one from context.allocator and never freed individually.
Entry :: struct {
    name:  string;
    value: int;
    next:  *Entry;
}

make_entry :: (i: int) -> *Entry {
    e := New(Entry);
    e.name  = sprint("key_%", i);       // 5..7 bytes
    e.value = i;
    return e;
}

build_list :: (count: int) -> *Entry {  // "library" code: allocates, never frees
    head, tail: *Entry;
    for i: 0..count-1 {
        e := make_entry(i);
        if tail  tail.next = e;  else head = e;
        tail = e;
    }
    return head;
}

list_sum :: (e: *Entry) -> int { s := 0; while e { s += e.value; e = e.next; } return s; }
gap :: (a: *void, b: *void) -> int { return cast(*u8) b - cast(*u8) a; }

Counts :: struct { calls, frees: int; }
counting_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    c := cast(*Counts) data;
    if mode == .ALLOCATE || mode == .RESIZE  c.calls += 1;
    if mode == .FREE  c.frees += 1;
    return context.default_allocator.proc(mode, size, old_size, old_memory, null);
}

main :: () {
    heap_counts: Counts;
    arena := Chunk_Arena.{backing = .{counting_proc, *heap_counts}};

    // Request 1: nobody knows the count in advance. Objects in the arena, index in temp.
    index: [..] *Entry;
    index.allocator = temp;
    kept: *Entry;
    {
        push_allocator(chunk_arena_proc, *arena);
        for i: 0..299 {
            e := make_entry(i);
            array_add(*index, e);
            if i == 0  kept = e;            // a pointer taken while the first chunk was filling up
        }
        alloc(10_000);                      // bigger than a chunk
    }
    print("request 1: 300 entries % bytes apart in % chunks of % bytes; the 10000-byte buffer got its own chunk\n",
        gap(index[0], index[1]), arena.chunks - 1, arena.chunk_size);
    index[0].value = 1000;                  // update through the index...
    print("pointer kept from the start sees an update made through the index: % (same object)\n", kept.value);
    reset_temporary_storage();              // the index is gone, the entries are not (yet)

    // End of request 1: one call. Request 2 reuses the kept chunk.
    before := heap_counts.calls;
    chunks_before := arena.chunks;
    arena_reset(*arena);
    print("reset: % chunk kept, % freed; ", arena.chunks, chunks_before - arena.chunks);
    {
        push_allocator(chunk_arena_proc, *arena);
        build_list(200);
    }
    print("request 2 (200 entries) made % new heap calls\n", heap_counts.calls - before);
    arena_release(*arena);
    print("release: heap calls %, frees %\n", heap_counts.calls, heap_counts.frees);

    // Contrast: entries stored by value inside a [..] move when it grows.
    pool: Flat_Pool;
    values: [..] Entry;
    values.allocator = .{flat_pool_allocator_proc, *pool};
    moves := 0;
    early: *Entry;
    for i: 0..299 {
        old_data := values.data;
        array_add(*values, .{value = i});
        if old_data && values.data != old_data  moves += 1;
        if i == 0  early = *values[0];      // a pointer into the array, taken early
    }
    print("[..] Entry: elements moved % times while growing to %\n", moves, values.count);
    values[0].value = 1000;
    print("pointer kept from the start reads % after an update to %: stale copy\n", early.value, values[0].value);
    fini(*pool);

    // The shipped answers, with the same "library" code.
    flat: Flat_Pool;
    {
        push_allocator(flat_pool_allocator_proc, *flat);
        h := build_list(300);
        print("Flat_Pool: 300 entries % bytes apart, % bytes in one reserved range, sum %\n",
            gap(h, h.next), flat.current_point - flat.memory_base, list_sum(h));
    }
    reset(*flat);                           // O(1): moves one pointer back
    fini(*flat);

    {
        before := context.temporary_storage.total_bytes_occupied;
        push_allocator(temp);
        h := build_list(300);
        print("temp: 300 entries % bytes apart, % bytes (sizes padded to 8), sum %\n",
            gap(h, h.next), context.temporary_storage.total_bytes_occupied - before, list_sum(h));
    }
    reset_temporary_storage();

    // A heap per lifetime: destroy_heap alone keeps the blocks; heap_free_all releases them.
    rp.rpmalloc_allocator_proc(.STARTUP, 0, 0, null, null);
    rpa := Allocator.{rp.rpmalloc_allocator_proc, null};
    owns :: (h: Allocator, p: *void) -> bool { return h.proc(.IS_THIS_YOURS, 0, 0, p, h.data) != null; }
    blocks: [3] *void;
    level: Allocator;
    first_heap: *void;
    same := true;
    for round: 0..2 {
        if round  destroy_heap(level);         // "end of the level", the way example 13 does it
        level = create_heap(rpa);
        if round == 0  first_heap = level.data;  else same &&= level.data == first_heap;
        blocks[round] = alloc(100,, level);
    }
    owned := 0;
    for blocks  if owns(level, it)  owned += 1;
    print("rpmalloc, 3 rounds of create_heap + 100 bytes + destroy_heap: same heap each time: %, it still owns % of the 3 blocks\n", same, owned);
    rp.heap_free_all(cast(*rp.Heap) level.data); // the call that actually frees
    destroy_heap(level);
    owned = 0;
    for blocks  if owns(level, it)  owned += 1;
    next := create_heap(rpa);
    print("heap_free_all, then destroy_heap: the heap owns % of them, the next create_heap starts empty: %\n",
        owned, next.data == first_heap && !owns(next, blocks[0]));
    destroy_heap(next);
}
