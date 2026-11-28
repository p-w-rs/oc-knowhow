// Situation 3 of 4: you do NOT know how long each object lives (an entity dies when the game
// says so, a connection when the peer hangs up), but every object has the SAME size.
// Answer: a pool of fixed-size slots with a free list (written here; 0.2.032 ships none).
// - Slots are carved from chunks taken from the pool's allocator. Chunks never move, so a
//   pointer to a live object stays valid; only the small array of chunk pointers grows.
// - Free slots form an INTRUSIVE free list: a free slot's own bytes hold the index of the next
//   free slot (a union with the value), so no side table is needed. add pops the head, remove
//   pushes onto it: both O(1), no search, no size header per object, and the slot freed last
//   (the one most likely still in cache) is handed out first.
// - Reuse makes plain indices and pointers dangerous: after remove + add, an old reference
//   points at the NEW occupant. Generational handles fix that: a Handle is (index, generation),
//   each slot counts its lives (odd = live, even = free, +1 on every add and remove), so a
//   handle from an earlier life no longer matches and pool_get returns null. Handle.{} is never
//   valid. Bucket_Array, the closest shipped relative, gives stable addresses and slot reuse,
//   but it scans occupied flags for a free slot and has no generations: a stale locator
//   silently finds the new occupant.
// - for_expansion makes `for pool` visit the live objects in slot order, with `remove it`.
// - The same pool works as an Allocator for ONE size: New(Node) takes a slot, free(p) gives it
//   back. A queue that pushes and pops 10000 nodes then needs one chunk instead of 10050 heap
//   allocations.
// EXPECT: 5 entities in chunks of 4 slots: 2 chunks, 40-byte slots, entity 0 kept its address: true
// EXPECT: removed "orc" from slot 2: live 4, the free list starts at slot 2
// EXPECT: added "elf": reused slot 2, generation 1 -> 3, handle {2, 3}
// EXPECT: old handle {2, 1} rejected: true; the new one finds "elf"
// EXPECT: Bucket_Array for contrast: its stale locator silently finds "elf"
// EXPECT: live in slot order: knight archer elf mage troll
// EXPECT: removed 2 with hp <= 0 while iterating, live 3: knight elf mage
// EXPECT: slots freed in the order 4 0 1 are reused as 1 0 4
// EXPECT: one slot used for 1000 lives: generation 2000, every earlier handle rejected: true
// EXPECT: Handle.{} is never valid: true
// EXPECT: queue, 10000 pushes and pops of 16-byte nodes: the pool took 1 chunk of 64 slots (24 bytes each); the default heap took 10050 allocations and 10050 frees
// EXPECT: after pool_release: heap blocks still held by the node pool: 0
#import "Basic";
#import "Bucket_Array";

Handle :: struct {
    index:      u32;
    generation: u32;
}

Slot :: struct (T: Type) {
    union {
        value:     T;
        next_free: s32;     // while the slot is free, its own bytes hold the free-list link
    }
    generation: u32;        // odd = live, even = free
    index:      u32;        // own position, so a raw pointer (Allocator FREE) finds its slot
}

Slot_Pool :: struct (T: Type, PER_CHUNK: int) {
    chunks:     [..] *[PER_CHUNK] Slot(T);   // grows; the chunks themselves never move
    free_head:  s32 = -1;                    // slot freed last, -1 = none
    used_slots: s32;                         // slots handed out at least once
    live:       int;
    allocator:  Allocator;                   // unset = context.allocator at first use
}

slot_at :: (pool: *Slot_Pool, index: s64) -> *Slot(pool.T) {
    return *pool.chunks[index / pool.PER_CHUNK].*[index % pool.PER_CHUNK];
}

take_slot :: (pool: *Slot_Pool) -> *Slot(pool.T) {
    slot: *Slot(pool.T);
    if pool.free_head >= 0 {                                 // O(1): pop the free list
        slot = slot_at(pool, pool.free_head);
        pool.free_head = slot.next_free;
    } else {
        if pool.used_slots == pool.chunks.count * pool.PER_CHUNK {
            if !pool.allocator.proc  remember_allocators(pool);
            pool.chunks.allocator = pool.allocator;
            Chunk :: [pool.PER_CHUNK] Slot(pool.T);
            array_add(*pool.chunks, cast(*Chunk) alloc(size_of(Chunk),, pool.allocator));
        }
        slot = slot_at(pool, pool.used_slots);
        slot.generation = 0;
        slot.index = cast(u32) pool.used_slots;
        pool.used_slots += 1;
    }
    slot.generation += 1;                                    // even -> odd: live
    pool.live += 1;
    return slot;
}

pool_add :: (pool: *Slot_Pool, value: pool.T) -> Handle, *pool.T {
    slot := take_slot(pool);
    slot.value = value;
    return .{slot.index, slot.generation}, *slot.value;
}

pool_get :: (pool: *Slot_Pool, h: Handle) -> *pool.T {
    if h.index >= cast(u32) pool.used_slots || !(h.generation & 1)  return null;
    slot := slot_at(pool, h.index);
    if slot.generation != h.generation  return null;         // freed, or reused since
    return *slot.value;
}

release_slot :: (pool: *Slot_Pool, slot: *Slot(pool.T)) {
    assert(slot.generation & 1 == 1, "slot % is already free", slot.index);
    slot.generation += 1;                                    // odd -> even: old handles die
    slot.next_free = pool.free_head;                         // O(1): push onto the free list
    pool.free_head = cast(s32) slot.index;
    pool.live -= 1;
}

pool_remove :: (pool: *Slot_Pool, h: Handle) -> bool {
    if !pool_get(pool, h)  return false;
    release_slot(pool, slot_at(pool, h.index));
    return true;
}

pool_release :: (pool: *Slot_Pool) {
    for pool.chunks  free(it,, pool.allocator);
    array_reset(*pool.chunks);
    pool.free_head, pool.used_slots, pool.live = -1, 0, 0;
}

for_expansion :: (pool: *Slot_Pool, body: Code, flags: For_Flags) #expand {
    #assert !(flags & .REVERSE) "Slot_Pool iterates forward only";
    for slot_index: 0..pool.used_slots-1 {
        slot := slot_at(pool, slot_index);
        if !(slot.generation & 1)  continue;                 // free slot
        #if flags & .POINTER  `it := *slot.value;
        else                  `it := slot.value;
        `it_index := slot_index;
        #insert (remove = { release_slot(pool, slot); }) body;
    }
}

Node :: struct {
    value: int;
    next:  *Node;
}

Node_Pool :: Slot_Pool(Node, 64);

// The pool as an Allocator for one size. The value sits at offset 0 of its slot, so the
// pointer handed out IS the slot pointer.
node_pool_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    pool := cast(*Node_Pool) data;
    if mode == {
      case .ALLOCATE;
        assert(size <= size_of(Node), "node pool: asked for % bytes, serves %", size, size_of(Node));
        return *take_slot(pool).value;
      case .RESIZE;
        assert(size <= size_of(Node), "node pool: cannot grow a block to % bytes", size);
        return ifx old_memory then old_memory else *take_slot(pool).value;
      case .FREE;
        if old_memory  release_slot(pool, cast(*Slot(Node)) old_memory);
        return null;
      case .IS_THIS_YOURS;
        for pool.chunks {
            start := cast(*u8) it;
            if old_memory >= start && old_memory < start + size_of(type_of(it.*))  return cast(*void) 1;
        }
        return null;
      case .CAPS;
        if old_memory { (cast(*string) old_memory).* = "example slot pool (one size)"; }
        return cast(*void) (Allocator_Caps.FREE | .IS_THIS_YOURS);
      case .STARTUP; #through;
      case .SHUTDOWN;
        return null;
      case;
        assert(false, "node pool: mode % is not supported", mode);
        return null;
    }
}

// Counts calls and blocks on their way to the default heap.
Counts :: struct { allocations, frees, blocks: int; }
counting_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    c := cast(*Counts) data;
    if mode == .ALLOCATE || (mode == .RESIZE && !old_memory) { c.allocations += 1; c.blocks += 1; }
    if mode == .FREE && old_memory { c.frees += 1; c.blocks -= 1; }
    return context.default_allocator.proc(mode, size, old_size, old_memory, null);
}

// A FIFO queue whose nodes are allocated on push and freed on pop: lifetimes unknown to the queue.
Queue :: struct { head, tail: *Node; }

push :: (q: *Queue, value: int) {
    n := New(Node);                         // from context.allocator
    n.value = value;
    if q.tail  q.tail.next = n;  else q.head = n;
    q.tail = n;
}

pop :: (q: *Queue) -> int {
    n := q.head;
    q.head = n.next;
    if !q.head  q.tail = null;
    value := n.value;
    free(n);
    return value;
}

run_queue :: (operations: int, depth: int) -> sum: int {
    q: Queue;
    sum := 0;
    for 0..depth-1  push(*q, it);
    for depth..depth+operations-1 { sum += pop(*q); push(*q, it); }
    while q.head  sum += pop(*q);
    return sum;
}

Entity :: struct {
    name: string;
    hp:   int;
    x, y: float32;
}

main :: () {
    pool: Slot_Pool(Entity, 4);
    names :: string.["knight", "archer", "orc", "mage", "troll"];
    hps   :: int.[30, 0, 12, 50, -5];
    handles: [5] Handle;
    first: *Entity;
    for names {
        h, p := pool_add(*pool, .{name = it, hp = hps[it_index]});
        handles[it_index] = h;
        if it_index == 0  first = p;
    }
    print("5 entities in chunks of 4 slots: % chunks, %-byte slots, entity 0 kept its address: %\n",
        pool.chunks.count, size_of(Slot(Entity)), pool_get(*pool, handles[0]) == first);

    orc := handles[2];
    pool_remove(*pool, orc);
    print("removed \"orc\" from slot %: live %, the free list starts at slot %\n", orc.index, pool.live, pool.free_head);

    elf := pool_add(*pool, .{name = "elf", hp = 20});
    print("added \"elf\": reused slot %, generation % -> %, handle %\n", elf.index, orc.generation, elf.generation, elf);
    print("old handle % rejected: %; the new one finds \"%\"\n", orc, pool_get(*pool, orc) == null, pool_get(*pool, elf).name);

    buckets: Bucket_Array(Entity, 4);
    stale := bucket_array_add(*buckets, .{name = "orc"});
    bucket_array_remove(*buckets, stale);
    bucket_array_add(*buckets, .{name = "elf"});
    print("Bucket_Array for contrast: its stale locator silently finds \"%\"\n", bucket_array_find(*buckets, stale).name);
    bucket_array_reset(*buckets);

    print("live in slot order:");
    for pool  print(" %", it.name);
    print("\n");

    removed := 0;
    for * pool  if it.hp <= 0 { remove it; removed += 1; }
    print("removed % with hp <= 0 while iterating, live %:", removed, pool.live);
    for pool  print(" %", it.name);
    print("\n");

    // LIFO reuse: the slot freed last is handed out first.
    pool_release(*pool);
    for 0..4  handles[it] = pool_add(*pool, .{hp = it});
    for i: int.[4, 0, 1]  pool_remove(*pool, handles[i]);
    print("slots freed in the order 4 0 1 are reused as");
    for 1..3  print(" %", pool_add(*pool, .{}).index);
    print("\n");
    pool_release(*pool);

    // Generations: every life of a slot gets its own number.
    lives: Slot_Pool(Entity, 4);
    old: [..] Handle;
    old.allocator = temp;
    for 1..1000 {
        h := pool_add(*lives, .{hp = it});
        array_add(*old, h);
        pool_remove(*lives, h);
    }
    all_rejected := true;
    for old  if pool_get(*lives, it)  all_rejected = false;
    print("one slot used for 1000 lives: generation %, every earlier handle rejected: %\n", slot_at(*lives, 0).generation, all_rejected);
    reset_temporary_storage();
    pool_add(*lives, .{});                                  // slot 0 live again
    print("Handle.{} is never valid: %\n", pool_get(*lives, .{}) == null);
    pool_release(*lives);

    // As an Allocator: the chunk is the only heap traffic of the pooled run.
    chunk_counts, heap_counts: Counts;
    nodes: Node_Pool;
    nodes.allocator = .{counting_proc, *chunk_counts};
    sum_pool := run_queue(10_000, 50,, Allocator.{node_pool_proc, *nodes});
    sum_heap := run_queue(10_000, 50,, Allocator.{counting_proc, *heap_counts});
    assert(sum_pool == sum_heap);
    print("queue, 10000 pushes and pops of %-byte nodes: the pool took % chunk of % slots (% bytes each); the default heap took % allocations and % frees\n",
        size_of(Node), nodes.chunks.count, nodes.PER_CHUNK, size_of(Slot(Node)), heap_counts.allocations, heap_counts.frees);
    pool_release(*nodes);
    print("after pool_release: heap blocks still held by the node pool: %\n", chunk_counts.blocks);
}
