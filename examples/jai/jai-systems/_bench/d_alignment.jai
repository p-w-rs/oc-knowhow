// d. Alignment: what a misaligned load or store costs, and #no_padding arrays.
//
// 1. Load latency: a chain of dependent 8-byte loads (each load reads the address of the next)
//    whose targets all sit at the same offset inside 16 KiB blocks: offset 0 is aligned; 4 is
//    misaligned inside a line; 60 and 124 cross a 64-byte (and, for 124, a 128-byte) line;
//    4092 crosses a 4 KiB page, 16380 a 16 KiB page. 4 blocks: the chain stays in L1.
// 2. Throughput: sum every u64 of a buffer at offset 0 (aligned) vs offset 4 (every 8th load of
//    a 64-byte line crosses into the next line), in L1 (16 KiB) and from DRAM (256 MiB on Linux,
//    128 MiB here and on the Mac is enough to leave every cache); and the same as read-modify-write.
// 3. Arrays of {u8, u64, u8}: padded (24 bytes, b aligned), reordered (16 bytes), #no_padding
//    (17 bytes, b misaligned in 7 of 8 elements): sum of b, ns per element, L1-sized and large.
// No atomics on misaligned addresses here: on x86 a locked access that spans two lines is a split
// lock (very slow; Linux may warn about or throttle it), on arm64 it faults.
#load "harness.jai";

// ---------------------------------------------------------------- 1. dependent loads

BLOCK  :: 16384;
BLOCKS :: 4;

chase :: (start: *u8, steps: s64) -> *u8 {
    p := start;
    for 1..steps p = (cast(**u8) p).*;
    return p;
}

chase_ns :: (offset: s64, steps: s64) -> Timing {
    memory, base := NewArray(BLOCK * BLOCKS + BLOCK, u8, alignment = BLOCK);
    defer free(base);
    // A ring through the blocks: block k's slot points at block k+1's slot.
    for k: 0..BLOCKS-1 {
        slot := memory.data + k * BLOCK + offset;
        next := memory.data + ((k + 1) % BLOCKS) * BLOCK + offset;
        memcpy(slot, *next, 8);
    }
    start := memory.data + offset;
    end: *u8;
    t := measure(#code { end = chase(start, steps); });
    if end != start && steps % BLOCKS == 0 print("chase broke at offset %\n", offset);
    return per_op(t, steps);
}

// ---------------------------------------------------------------- 2. streaming

sum_u64 :: (p: *u8, count: s64, passes: s64) -> u64 {
    s: u64;
    for 1..passes for i: 0..count-1 { s += (cast(*u64) (p + i * 8)).*; }
    return s;
}

add_u64 :: (p: *u8, count: s64, passes: s64) {
    for 1..passes for i: 0..count-1 { q := cast(*u64) (p + i * 8); q.* += 1; }
}

// ---------------------------------------------------------------- 3. #no_padding arrays

Padded    :: struct { a: u8; b: u64; c: u8; }
Reordered :: struct { b: u64; a: u8; c: u8; }
Packed    :: struct { a: u8; b: u64; c: u8; } #no_padding
#assert size_of(Padded) == 24 && size_of(Reordered) == 16 && size_of(Packed) == 17;

sum_b :: (items: [] $T, passes: s64) -> u64 {
    s: u64;
    for 1..passes for items s += it.b;
    return s;
}

stride_row :: (name: string, $T: Type, counts: [] s64, checksum: *u64) {
    print("| % (% bytes) |", name, size_of(T));
    for n: counts {
        items := NewArray(n, T, alignment = 64);
        for * items it.b = xx it_index;
        passes := max(1, 8_000_000 / n);
        result: u64;
        t := per_op(measure(#code { result = sum_b(items, passes); }), passes * n);
        checksum.* += result;
        if result != cast(u64) (passes * (n * (n - 1) / 2)) print("WRONG SUM for %\n", name);
        print(" % |", cell(t));
        array_free(items);
    }
    print("\n");
}

main :: () {
    parse_common_args();
    checksum: u64;

    print("### d. Alignment\n\n");
    print("**Dependent 8-byte loads at an offset inside 16 KiB blocks (4 blocks: L1), ns per load, median of % runs (min)**\n\n", runs);
    print_table_header("offset", .["ns per load", "crosses"]);
    steps : s64 = ifx quick then 4_000_000 else 40_000_000;
    for offset: s64.[0, 4, 60, 124, 4092, 16380] {
        crosses := "nothing (aligned)";
        if offset == 4     crosses = "nothing (misaligned inside a line)";
        if offset == 60    crosses = "a 64-byte line";
        if offset == 124   crosses = "a 64- and a 128-byte line";
        if offset == 4092  crosses = "a 4 KiB page (and lines)";
        if offset == 16380 crosses = "a 16 KiB page (and lines)";
        print("| % | % | % |\n", offset, cell(chase_ns(offset, steps)), crosses);
    }

    print("\n**Summing / incrementing every u64 of a buffer: ns per u64, aligned (offset 0) vs offset 4**\n\n");
    print_table_header("buffer", .["sum, offset 0", "sum, offset 4", "+= 1, offset 0", "+= 1, offset 4"]);
    for bytes: s64.[16 * 1024, ifx quick then 16 * 1024 * 1024 else 128 * 1024 * 1024] {
        memory, base := NewArray(bytes + 64, u8, alignment = 4096);
        memset(memory.data, 1, memory.count);
        count := bytes / 8 - 1;
        passes := max(1, 16_000_000 / count);
        r0, r4: u64;
        s0 := per_op(measure(#code { r0 = sum_u64(memory.data, count, passes); }), passes * count);
        s4 := per_op(measure(#code { r4 = sum_u64(memory.data + 4, count, passes); }), passes * count);
        a0 := per_op(measure(#code { add_u64(memory.data, count, passes); }), passes * count);
        a4 := per_op(measure(#code { add_u64(memory.data + 4, count, passes); }), passes * count);
        checksum += r0 + r4 + sum_u64(memory.data, count, 1);
        label := ifx bytes < 1024 * 1024 then tprint("% KiB", bytes / 1024) else tprint("% MiB", bytes / (1024 * 1024));
        print("| % | % | % | % | % |\n", label, cell(s0), cell(s4), cell(a0), cell(a4));
        free(base);
    }

    print("\n**Arrays of {u8, u64, u8}: summing b, ns per element**\n\n");
    counts := s64.[1024, ifx quick then 1_000_000 else 4_000_000];
    print_table_header("layout", .[tprint("% elements", counts[0]), tprint("% elements", counts[1])]);
    stride_row("padded", Padded, counts, *checksum);
    stride_row("reordered", Reordered, counts, *checksum);
    stride_row("#no_padding", Packed, counts, *checksum);
    print("\nChecksum %.\n\n", checksum);
}
