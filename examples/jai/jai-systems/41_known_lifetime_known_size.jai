// Situation 1 of 4: you know HOW LONG the memory lives and HOW MUCH of it you need.
// The cheapest case there is: one allocation of the exact size (or none), no growth, no copies,
// no per-object bookkeeping, everything contiguous, and one free at the end (or none at all for
// data that lives until exit: the OS takes it back).
// - Count first, then allocate once: pass 1 counts the rows, pass 2 fills arrays of exactly
//   that length. The names are views into the input text: no string allocations at all.
// - Several arrays in ONE block: add up the column sizes, each start rounded up to 64 bytes,
//   allocate the total and slice [] views out of it. General heaps hand out 16-byte aligned
//   blocks, so ask for 63 extra bytes and round the address up (NewArray's alignment parameter
//   over-allocates the same way); free the pointer you got back, not the rounded one.
// - A size known at compile time needs no allocator: [N] T on the stack or inside a struct.
// - A "known size" that is only an UPPER BOUND: reserve the bound once and refuse anything past
//   it (unused capacity is the price, regrowth never happens), or fill a bound-sized scratch
//   buffer in temp and keep an exact-size copy.
// A counting wrapper around the heap makes every call visible; the counts are the same everywhere.
// EXPECT: pass 1: 6 rows
// EXPECT: one block, 4 columns at offsets 0, 64, 192, 256; 262 bytes + 63 for alignment
// EXPECT: every column starts on a 64-byte boundary: true
// EXPECT: loading made 1 heap call; the names are views into the input: true
// EXPECT: best: ada 91.5; passed: 4 of 6
// EXPECT: histogram in a struct (88 bytes), 0 heap calls: [0, 0, 0, 0, 1, 1, 1, 1, 1, 1]
// EXPECT: bound 8 reserved once: 8 accepted, 4 refused, capacity 8, heap calls 1
// EXPECT: passing ids [7, 12, 21, 9]: bound-sized scratch in temp, then 1 exact heap block of 16 bytes
// EXPECT: 1000 items: growing [..] made 8 heap calls, reserved [..] made 1
// EXPECT: the whole table freed with 1 call
#import "Basic";
#import "String";

Calls :: struct {
    allocate, resize, free: int;
    bytes: int;                 // requested by ALLOCATE
    backing: Allocator;
}

counting_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    calls := cast(*Calls) data;
    if mode == .ALLOCATE { calls.allocate += 1; calls.bytes += size; }
    if mode == .RESIZE    calls.resize += 1;
    if mode == .FREE      calls.free   += 1;
    return calls.backing.proc(mode, size, old_size, old_memory, calls.backing.data);
}

heap_calls :: (c: Calls) -> int { return c.allocate + c.resize; }

INPUT :: #string END
7,ada,91.5
12,grace,78
3,edsger,55.25
21,barbara,88
5,ken,42
9,dennis,67.5
END

Table :: struct {
    ids:    [] u32;
    names:  [] string;      // views into INPUT, which outlives the table
    scores: [] float32;
    passed: [] bool;
    block:  *void;          // the one allocation behind all four columns
}

LINE :: 64;
round_up :: (n: int, to: int) -> int { return (n + to - 1) & ~(to - 1); }

next_line :: (rest: *string) -> string {
    found, line, after := split_from_left(rest.*, #char "\n");
    rest.* = after;
    return line;
}

count_rows :: (text: string) -> int {
    rows := 0;
    rest := text;
    while rest.count  if next_line(*rest).count  rows += 1;
    return rows;
}

load_table :: (text: string, rows: int) -> Table, [4] int, int {
    offsets: [4] int;                                   // where each column starts in the block
    offsets[1] = round_up(offsets[0] + rows * size_of(u32),     LINE);
    offsets[2] = round_up(offsets[1] + rows * size_of(string),  LINE);
    offsets[3] = round_up(offsets[2] + rows * size_of(float32), LINE);
    total     := offsets[3] + rows * size_of(bool);

    t: Table;
    t.block = alloc(total + LINE - 1);                  // the only heap call
    base := cast(*u8) round_up(cast(int) t.block, LINE);
    t.ids.data    = cast(*u32)     (base + offsets[0]);
    t.names.data  = cast(*string)  (base + offsets[1]);
    t.scores.data = cast(*float32) (base + offsets[2]);
    t.passed.data = cast(*bool)    (base + offsets[3]);
    t.ids.count, t.names.count, t.scores.count, t.passed.count = rows, rows, rows, rows;

    rest := text;
    row := 0;
    while rest.count {
        line := next_line(*rest);
        if !line.count continue;
        _, id_text, after_id := split_from_left(line, #char ",");
        _, name, score_text  := split_from_left(after_id, #char ",");
        score := string_to_float(score_text);
        t.ids[row], t.names[row], t.scores[row], t.passed[row] = cast(u32) to_integer(id_text), name, score, score >= 60;
        row += 1;
    }
    return t, offsets, total;
}

Histogram :: struct {
    buckets: [10] int;      // size known when compiling: lives wherever the struct lives
    total:   int;
}

add_bounded :: (a: *[..] $T, item: T) -> bool {
    if a.count == a.allocated  return false;        // full: report it instead of regrowing
    array_add(a, item);
    return true;
}

main :: () {
    calls := Calls.{backing = context.allocator};
    counting := Allocator.{counting_proc, *calls};

    rows := count_rows(INPUT);
    print("pass 1: % rows\n", rows);

    table, offsets, total := load_table(INPUT, rows,, counting);
    print("one block, 4 columns at offsets %, %, %, %; % bytes + % for alignment\n",
        offsets[0], offsets[1], offsets[2], offsets[3], total, LINE - 1);
    starts := (*void).[table.ids.data, table.names.data, table.scores.data, table.passed.data];
    aligned := true;
    for starts  if (cast(int) it) % LINE  aligned = false;
    print("every column starts on a 64-byte boundary: %\n", aligned);
    in_input := table.names[0].data >= INPUT.data && table.names[0].data < INPUT.data + INPUT.count;
    print("loading made % heap call; the names are views into the input: %\n", heap_calls(calls), in_input);

    best, passed := 0, 0;
    for table.scores {
        if it > table.scores[best]  best = it_index;
        if table.passed[it_index]  passed += 1;
    }
    print("best: % %; passed: % of %\n", table.names[best], table.scores[best], passed, rows);

    before := heap_calls(calls);
    histogram: Histogram;                               // on the stack: no allocation at all
    for table.scores { histogram.buckets[cast(int) (it / 10)] += 1; histogram.total += 1; }
    print("histogram in a struct (% bytes), % heap calls: %\n", size_of(Histogram), heap_calls(calls) - before, histogram.buckets);

    // Upper bound, kind 1: reserve the bound, refuse what does not fit.
    MAX_IDS :: 8;
    up := Calls.{backing = context.allocator};
    ids: [..] u32;
    ids.allocator = .{counting_proc, *up};
    array_reserve(*ids, MAX_IDS);
    accepted, refused := 0, 0;
    for 1..2  for table.ids {                           // 12 ids offered, 8 fit
        if add_bounded(*ids, it) accepted += 1; else refused += 1;
    }
    print("bound % reserved once: % accepted, % refused, capacity %, heap calls %\n",
        MAX_IDS, accepted, refused, ids.allocated, heap_calls(up));
    array_free(ids);

    // Upper bound, kind 2: at most 'rows' rows pass, so fill a rows-sized scratch buffer in temp,
    // then keep an exact-size copy on the heap.
    exact := Calls.{backing = context.allocator};
    scratch := NewArray(rows, u32, initialize = false,, temp);
    n := 0;
    for table.ids  if table.passed[it_index] { scratch[n] = it; n += 1; }
    kept := array_copy(array_view(scratch, 0, n),, Allocator.{counting_proc, *exact});
    reset_temporary_storage();
    print("passing ids %: bound-sized scratch in temp, then % exact heap block of % bytes\n", kept, heap_calls(exact), exact.bytes);
    free(kept.data,, Allocator.{counting_proc, *exact});

    // The cost you avoid: a [..] that does not know its size regrows (and copies) as it goes.
    grow     := Calls.{backing = context.allocator};
    reserved := Calls.{backing = context.allocator};
    a, b: [..] int;
    a.allocator = .{counting_proc, *grow};
    b.allocator = .{counting_proc, *reserved};
    array_reserve(*b, 1000);
    for 1..1000 { array_add(*a, it); array_add(*b, it); }
    print("1000 items: growing [..] made % heap calls, reserved [..] made %\n", heap_calls(grow), heap_calls(reserved));
    array_free(a);
    array_free(b);

    free(table.block,, counting);                       // all four columns at once
    print("the whole table freed with % call\n", calls.free);
}
