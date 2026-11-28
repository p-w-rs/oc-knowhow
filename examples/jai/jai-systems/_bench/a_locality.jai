// a. Locality: sum one value per element through linked lists built in different ways, versus a
// plain array. Reports nanoseconds per element (median of the timed runs, min in parentheses).
// The list nodes are 16 bytes (next pointer + value); sizes are given as n nodes * 16 bytes.
// Every list walks its nodes in list order; only WHERE the nodes sit in memory differs:
//   array of s64           the values alone, contiguous (8 bytes each; the loop vectorizes)
//   index list in an array 8-byte nodes {value: s32, next: s32} in one array, linked in order
//   list, Flat_Pool        nodes from a bump arena: contiguous, in list order
//   list, heap in order    New(Node) from the default heap, nothing else allocated in between
//   list, heap + mixed     8..64-byte blocks allocated between the nodes (and kept)
//   list, heap + same size 16-byte blocks allocated between the nodes (and kept)
//   list, heap churned     built in order, then a random half of the nodes freed and allocated
//                          again in random order: those positions get recycled blocks
//   list, slot pool churn  the same churn in a fixed-size pool with a LIFO free list
//   slot pool scan         the churned pool walked in slot (memory) order instead of list order
//   Bucket_Array scan      for-loop over a Bucket_Array(Node, 1024)
//   list, shuffled         nodes in one array, linked in a random order (the worst case)
#load "harness.jai";
#import "Flat_Pool";
#import "Bucket_Array";
#import "String";

Node :: struct {
    next:  *Node;
    value: s64;
}

Index_Node :: struct {
    value: s32;
    next:  s32;            // -1 ends the list
}

Case :: enum {
    ARRAY;
    INDEX_LIST;
    ARENA_LIST;
    HEAP_IN_ORDER;
    HEAP_MIXED_BETWEEN;
    HEAP_SAME_BETWEEN;
    HEAP_CHURNED;
    SLOT_POOL_CHURNED;
    SLOT_POOL_SCAN;
    BUCKET_ARRAY_SCAN;
    SHUFFLED;
}

CASE_NAMES :: string.[
    "array of s64",
    "index list in an array",
    "list, Flat_Pool",
    "list, heap in order",
    "list, heap + mixed sizes between",
    "list, heap + same size between",
    "list, heap churned",
    "list, slot pool churned",
    "slot pool scan (after churn)",
    "Bucket_Array scan",
    "list, shuffled",
];
CASE_COUNT :: CASE_NAMES.count;
#assert CASE_COUNT == enum_highest_value(Case) + 1;

SIZES        :: s64.[2048, 65536, 524288, 2097152, 8388608];
SIZE_LABELS  :: string.["32 KiB", "1 MiB", "8 MiB", "32 MiB", "128 MiB"];
TARGET       :: 4_000_000;    // elements visited per timed run (passes = TARGET / n, at least 1)

// ---------------------------------------------------------------- kernels
// The salt changes every pass, so no pass can reuse another one's result.

walk_list :: (head: *Node, passes: s64, salt: s64) -> s64 {
    sum: s64;
    for p: 1..passes {
        s := salt + p;
        node := head;
        while node {
            sum += node.value ^ s;
            node = node.next;
        }
    }
    return sum;
}

sum_values :: (values: [] s64, passes: s64, salt: s64) -> s64 {
    sum: s64;
    for p: 1..passes {
        s := salt + p;
        for values sum += it ^ s;
    }
    return sum;
}

walk_index_list :: (nodes: [] Index_Node, first: s32, passes: s64, salt: s64) -> s64 {
    sum: s64;
    for p: 1..passes {
        s := salt + p;
        i := first;
        while i >= 0 {
            node := nodes[i];
            sum += node.value ^ s;
            i = node.next;
        }
    }
    return sum;
}

scan_slot_pool :: (pool: *Slot_Pool, passes: s64, salt: s64) -> s64 {
    sum: s64;
    for p: 1..passes {
        s := salt + p;
        for pool.slots if pool.occupied[it_index] sum += it.value ^ s;
    }
    return sum;
}

scan_bucket_array :: (array: *Bucket_Array(Node, 1024), passes: s64, salt: s64) -> s64 {
    sum: s64;
    for p: 1..passes {
        s := salt + p;
        for array.* sum += it.value ^ s;
    }
    return sum;
}

plain_sum :: (head: *Node) -> s64 {
    sum: s64;
    while head { sum += head.value; head = head.next; }
    return sum;
}

// ---------------------------------------------------------------- a fixed-size slot pool
// Capacity fixed up front; freed slots go on a LIFO free list threaded through their next field.

Slot_Pool :: struct {
    slots:     [] Node;
    occupied:  [] bool;
    free_list: *Node;
    unused:    s64;        // slots[unused..] were never handed out
}

slot_pool_init :: (pool: *Slot_Pool, capacity: s64) {
    pool.slots    = NewArray(capacity, Node, initialize = false);
    pool.occupied = NewArray(capacity, bool);
}

slot_get :: (pool: *Slot_Pool) -> *Node {
    node := pool.free_list;
    if node {
        pool.free_list = node.next;
    } else {
        assert(pool.unused < pool.slots.count, "slot pool is full");
        node = *pool.slots[pool.unused];
        pool.unused += 1;
    }
    pool.occupied[node - pool.slots.data] = true;
    return node;
}

slot_free :: (pool: *Slot_Pool, node: *Node) {
    pool.occupied[node - pool.slots.data] = false;
    node.next = pool.free_list;
    pool.free_list = node;
}

slot_pool_release :: (pool: *Slot_Pool) {
    array_free(pool.slots);
    array_free(pool.occupied);
    pool.* = .{};
}

// ---------------------------------------------------------------- list building

// Links nodes in array order and numbers them 1..n.
link :: (order: [] *Node) -> *Node {
    for order {
        it.value = it_index + 1;
        it.next  = ifx it_index + 1 < order.count then order[it_index + 1] else null;
    }
    return order[0];
}

// Frees a random half of the nodes (in random order), then allocates replacements for the same
// list positions in the same order. The allocator decides which blocks the replacements get.
churn :: (order: [] *Node, pool: *Slot_Pool = null) {   // pool null = the default heap
    victims := NewArray(order.count, s64, initialize = false);
    defer array_free(victims);
    for * victims it.* = it_index;
    shuffle(victims);
    half := array_view(victims, 0, order.count / 2);
    for half {
        if pool slot_free(pool, order[it]);
        else    free(order[it]);
    }
    for half order[it] = ifx pool then slot_get(pool) else New(Node, initialize = false);
}

// ---------------------------------------------------------------- where the nodes ended up

Layout :: struct {
    measured:      bool;
    sequential:    float64;  // share of steps where the next node is the next 16 bytes
    backwards:     float64;  // share of steps that go to a lower address
    line_changes:  float64;  // per node: steps that leave the current 64-byte line
}

layout_of :: (order: [] *Node) -> Layout {
    result := Layout.{measured = true};
    sequential, backwards, changes: s64;
    for 1..order.count-1 {
        a := cast(s64) order[it-1];
        b := cast(s64) order[it];
        if b - a == size_of(Node) sequential += 1;
        if b < a                  backwards += 1;
        if a / 64 != b / 64       changes += 1;
    }
    steps := cast(float64) (order.count - 1);
    result.sequential   = sequential / steps;
    result.backwards    = backwards / steps;
    result.line_changes = changes / steps;
    return result;
}

// ---------------------------------------------------------------- one case at one size

Result :: struct {
    timing:  Timing;       // ns per element
    correct: bool;
    layout:  Layout;
}

run_case :: (c: Case, n: s64) -> Result {
    passes := max(1, TARGET / n);
    expected := n * (n + 1) / 2;
    checksum: s64;
    salt: s64;
    result: Result;

    order := NewArray(n, *Node, initialize = false);
    defer array_free(order);

    if c == {
      case .ARRAY;
        values := NewArray(n, s64, initialize = false);
        for * values it.* = it_index + 1;
        plain: s64;
        for values plain += it;
        result.correct = plain == expected;
        result.timing = measure(#code { salt += 1; checksum += sum_values(values, passes, salt); });
        array_free(values);

      case .INDEX_LIST;
        nodes := NewArray(n, Index_Node, initialize = false);
        for * nodes { it.value = cast(s32) (it_index + 1); it.next = cast(s32) (ifx it_index + 1 < n then it_index + 1 else -1); }
        plain: s64;
        i: s32 = 0;
        while i >= 0 { plain += nodes[i].value; i = nodes[i].next; }
        result.correct = plain == expected;
        result.timing = measure(#code { salt += 1; checksum += walk_index_list(nodes, 0, passes, salt); });
        array_free(nodes);

      case .ARENA_LIST;
        pool: Flat_Pool;
        arena := Allocator.{flat_pool_allocator_proc, *pool};
        {
            push_allocator(arena);
            for 0..n-1 order[it] = New(Node, initialize = false);
        }
        head := link(order);
        result.layout = layout_of(order);
        result.correct = plain_sum(head) == expected;
        result.timing = measure(#code { salt += 1; checksum += walk_list(head, passes, salt); });
        fini(*pool);

      case .HEAP_IN_ORDER; #through;
      case .HEAP_MIXED_BETWEEN; #through;
      case .HEAP_SAME_BETWEEN; #through;
      case .HEAP_CHURNED;
        others: [..] *void;
        array_reserve(*others, ifx c == .HEAP_MIXED_BETWEEN || c == .HEAP_SAME_BETWEEN then n else 0);
        for 0..n-1 {
            order[it] = New(Node, initialize = false);
            if c == .HEAP_MIXED_BETWEEN array_add(*others, alloc(cast(s64) (8 + random_get() % 57)));
            if c == .HEAP_SAME_BETWEEN  array_add(*others, alloc(size_of(Node)));
        }
        if c == .HEAP_CHURNED churn(order);
        head := link(order);
        result.layout = layout_of(order);
        result.correct = plain_sum(head) == expected;
        result.timing = measure(#code { salt += 1; checksum += walk_list(head, passes, salt); });
        for order free(it);
        for others free(it);
        array_free(others);

      case .SLOT_POOL_CHURNED; #through;
      case .SLOT_POOL_SCAN;
        pool: Slot_Pool;
        slot_pool_init(*pool, n);
        for 0..n-1 order[it] = slot_get(*pool);
        churn(order, *pool);
        head := link(order);
        result.correct = plain_sum(head) == expected;
        if c == .SLOT_POOL_CHURNED {
            result.layout = layout_of(order);
            result.timing = measure(#code { salt += 1; checksum += walk_list(head, passes, salt); });
        } else {
            result.timing = measure(#code { salt += 1; checksum += scan_slot_pool(*pool, passes, salt); });
        }
        slot_pool_release(*pool);

      case .BUCKET_ARRAY_SCAN;
        buckets: Bucket_Array(Node, 1024);
        for 0..n-1 bucket_array_add(*buckets, .{value = it + 1});
        plain: s64;
        for buckets plain += it.value;
        result.correct = plain == expected;
        result.timing = measure(#code { salt += 1; checksum += scan_bucket_array(*buckets, passes, salt); });
        bucket_array_reset(*buckets);

      case .SHUFFLED;
        nodes := NewArray(n, Node, initialize = false);
        for 0..n-1 order[it] = *nodes[it];
        shuffle(order);
        head := link(order);
        result.layout = layout_of(order);
        result.correct = plain_sum(head) == expected;
        result.timing = measure(#code { salt += 1; checksum += walk_list(head, passes, salt); });
        array_free(nodes);
    }

    result.timing = per_op(result.timing, passes * n);
    total_checksum += checksum;
    return result;
}

total_checksum: s64;

main :: () {
    // Optional: case=<row> size=<column> (0-based) measures one cell only, e.g. for perf stat.
    only_case, only_size := -1, -1;
    for parse_common_args() {
        if begins_with(it, "case=") only_case = string_to_int(slice(it, 5, it.count - 5));
        if begins_with(it, "size=") only_size = string_to_int(slice(it, 5, it.count - 5));
    }
    random_seed(2026);
    size_count := ifx quick then 3 else SIZES.count;
    sizes, cases: [..] s64;
    for 0..size_count-1 if only_size < 0 || it == only_size array_add(*sizes, it);
    for 0..CASE_COUNT-1 if only_case < 0 || it == only_case array_add(*cases, it);

    print("### a. Locality: ns per element, median of % runs (min)\n\n", runs);
    print("Node = 16 bytes (next pointer + s64). A column's size is n nodes * 16 bytes; the s64 array and the 8-byte index nodes take half of that. Each timed run visits at least % elements.\n\n", TARGET);

    results: [CASE_COUNT][SIZES.count] Result;
    for size_index: sizes {
        for c: cases results[c][size_index] = run_case(cast(Case) c, SIZES[size_index]);
    }

    columns: [..] string;
    for sizes array_add(*columns, tprint("% (n = %)", SIZE_LABELS[it], SIZES[it]));
    print_table_header("case", columns);
    all_correct := true;
    for c: cases {
        print("| % |", CASE_NAMES[c]);
        for s: sizes {
            print(" % |", cell(results[c][s].timing));
            if !results[c][s].correct all_correct = false;
        }
        print("\n");
    }
    print("\nEvery structure summed to n(n+1)/2: %. Checksum %.\n\n", all_correct, total_checksum);

    print("Where the list nodes ended up, per size: share of steps to the next 16 bytes / share of steps backwards / 64-byte line changes per node (0.25 = four nodes per line, 1 = a new line at every node).\n\n");
    print_table_header("list", columns);
    for c: cases {
        if !results[c][sizes[0]].layout.measured continue;
        print("| % |", CASE_NAMES[c]);
        for s: sizes {
            layout := results[c][s].layout;
            print(" % / % / % |", number(layout.sequential), number(layout.backwards), number(layout.line_changes));
        }
        print("\n");
    }
    print("\n");
}
