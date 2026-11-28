// Locality: where the allocator puts linked-list nodes decides how many cache lines a walk touches.
// A walk over a list loads one node, reads its next pointer, loads the next node: when the nodes sit
// side by side (each next is exactly size_of(Node) ahead) the walk streams through memory like an
// array and the hardware prefetchers keep up; when they are scattered every step is a cache miss.
// Measured on 0.2.032 (the stderr line shows this machine's raw counts):
// - Flat_Pool (any bump arena): nodes are always contiguous, in allocation order.
// - The default heap (C malloc on arm64 macOS, an rpmalloc variant on x64) hands out blocks from
//   per-size-class runs: nodes allocated in a row are nearly contiguous, and allocations of OTHER
//   sizes in between land in other runs, so they barely disturb the nodes. Allocations of the SAME
//   size class in between halve the density (each node then shares its line with a stranger).
// - After churn (free a random half, allocate again) the heap reuses freed blocks newest-first:
//   the new nodes are scattered and mostly ordered BACKWARDS in memory.
// - An index-linked list in one array has its locality by construction and smaller nodes.
// Timings for all of these are in _bench/ and reference/caches.md ("Lists, arrays and allocators").
// EXPECT: Node is 16 bytes; 4096 nodes per list
// EXPECT: arena (Flat_Pool): 4095 of 4095 steps are exactly +16 bytes; 1024 lines of 64 B, 512 of 128 B
// EXPECT: heap, nodes allocated in a row: at least 90 percent of steps are +16 bytes: true
// EXPECT: heap, 17..256-byte allocations in between: at least 90 percent of steps are +16 bytes: true
// EXPECT: heap, 16-byte allocations in between: under 10 percent of steps are +16 bytes: true; at least 1.5x the lines: true
// EXPECT: heap after churn: over half of the steps go backwards: true; at least 1.5x the lines: true
// EXPECT: index-linked list in one array: 8-byte nodes, 4096 nodes in 512 lines of 64 B
// EXPECT: every list sums to 8390656: true
// EXPECT-CONTAINS: raw counts on this machine:
#import "Basic";
#import "Flat_Pool";
#import "Random";
#import "Sort";

Node :: struct {
    next:  *Node;
    value: s64;
}

Index_Node :: struct {      // a list inside one array: links are 32-bit indices
    value: s32;
    next:  s32;             // -1 ends the list
}

N :: 4096;

Layout :: struct {
    plus_size: int;         // steps where next == this + size_of(Node)
    backwards: int;         // steps where next < this
    lines_64:  int;         // distinct 64-byte lines holding nodes
    lines_128: int;
}

layout_of :: (nodes: [] *Node) -> Layout {
    result: Layout;
    for 1..nodes.count-1 {
        step := cast(s64) nodes[it] - cast(s64) nodes[it-1];
        if step == size_of(Node) result.plus_size += 1;
        if step < 0              result.backwards += 1;
    }
    result.lines_64  = distinct_lines(nodes, 64);
    result.lines_128 = distinct_lines(nodes, 128);
    return result;
}

distinct_lines :: (nodes: [] *Node, line: u64) -> int {
    ids := NewArray(nodes.count, u64,, temp);
    for nodes ids[it_index] = (cast(u64) it) / line;
    quick_sort(ids, (a: u64, b: u64) -> s64 { return ifx a < b then -1 else ifx a > b then 1 else 0; });
    count := 0;
    for ids if it_index == 0 || it != ids[it_index-1] count += 1;
    return count;
}

// Links the nodes in array order and fills in values 1..N, then walks the list.
link_and_sum :: (nodes: [] *Node) -> s64 {
    for nodes {
        it.value = it_index + 1;
        it.next  = ifx it_index + 1 < nodes.count then nodes[it_index + 1] else null;
    }
    sum: s64;
    node := nodes[0];
    while node { sum += node.value; node = node.next; }
    return sum;
}

main :: () {
    random_seed(46);
    print("Node is % bytes; % nodes per list\n", size_of(Node), N);
    sums: [..] s64;
    raw: String_Builder;

    // 1. A bump arena: every New is the previous one plus 16 bytes.
    pool: Flat_Pool;
    arena := Allocator.{flat_pool_allocator_proc, *pool};
    nodes: [N] *Node;
    for 0..N-1 nodes[it] = New(Node,, arena);
    arena_layout := layout_of(nodes);
    array_add(*sums, link_and_sum(nodes));
    print("arena (Flat_Pool): % of % steps are exactly +% bytes; % lines of 64 B, % of 128 B\n",
        arena_layout.plus_size, N - 1, size_of(Node), arena_layout.lines_64, arena_layout.lines_128);

    // 2. The default heap, nothing else allocated in between.
    for 0..N-1 nodes[it] = New(Node);
    in_a_row := layout_of(nodes);
    array_add(*sums, link_and_sum(nodes));
    print("heap, nodes allocated in a row: at least 90 percent of steps are +16 bytes: %\n", in_a_row.plus_size >= N * 9 / 10);
    print_to_builder(*raw, "in a row %/% +16; ", in_a_row.plus_size, N - 1);

    // 3. Other sizes in between (a name string per node, say): different size classes.
    for 0..N-1 {
        nodes[it] = New(Node);
        other := alloc(cast(s64) (17 + random_get() % 240));   // 17..256 bytes, never the 16-byte class
    }
    other_sizes := layout_of(nodes);
    array_add(*sums, link_and_sum(nodes));
    print("heap, 17..256-byte allocations in between: at least 90 percent of steps are +16 bytes: %\n", other_sizes.plus_size >= N * 9 / 10);
    print_to_builder(*raw, "other sizes %/% +16; ", other_sizes.plus_size, N - 1);

    // 4. The same size class in between: every other block belongs to someone else.
    for 0..N-1 {
        nodes[it] = New(Node);
        stranger := alloc(16);
    }
    same_size := layout_of(nodes);
    array_add(*sums, link_and_sum(nodes));
    print("heap, 16-byte allocations in between: under 10 percent of steps are +16 bytes: %; at least 1.5x the lines: %\n",
        same_size.plus_size < N / 10, same_size.lines_64 * 2 >= arena_layout.lines_64 * 3);
    print_to_builder(*raw, "same size %/% +16, % lines; ", same_size.plus_size, N - 1, same_size.lines_64);

    // 5. Churn: allocate 2N, free a random half, then allocate the list.
    crowd: [2 * N] *Node;
    for 0..crowd.count-1 crowd[it] = New(Node);
    for crowd if random_get() % 2 == 0 free(it);
    for 0..N-1 nodes[it] = New(Node);
    churned := layout_of(nodes);
    array_add(*sums, link_and_sum(nodes));
    print("heap after churn: over half of the steps go backwards: %; at least 1.5x the lines: %\n",
        churned.backwards > N / 2, churned.lines_64 * 2 >= arena_layout.lines_64 * 3);
    print_to_builder(*raw, "churn % backwards, % lines", churned.backwards, churned.lines_64);

    // 6. An index-linked list: one array, 8-byte nodes, valid after a copy or a save to disk.
    list := NewArray(N, Index_Node);
    for * list { it.value = cast(s32) (it_index + 1); it.next = cast(s32) (ifx it_index + 1 < N then it_index + 1 else -1); }
    index_sum: s64;
    i: s32 = 0;
    while i >= 0 { index_sum += list[i].value; i = list[i].next; }
    array_add(*sums, index_sum);
    print("index-linked list in one array: %-byte nodes, % nodes in % lines of 64 B\n", size_of(Index_Node), N, N * size_of(Index_Node) / 64);

    same := true;
    for sums if it != sums[0] same = false;
    print("every list sums to %: %\n", sums[0], same && sums[0] == N * (N + 1) / 2);
    print("raw counts on this machine: %\n", builder_to_string(*raw), to_standard_error = true);
}
