// Alignment facts: what Jai gives you to see and control where bytes land.
// - Natural alignment: a value of N bytes (N = 1, 2, 4, 8) sits at an address divisible by N; a
//   struct takes its largest member's alignment and its size rounds up to a multiple of it, so the
//   compiler pads (declaration order is kept: put big members first, example 30).
// - Jai has no align_of. Type_Info_Struct got an `alignment` field in 0.2.030, but in 0.2.032 it
//   reads -1 for any struct that appears in the type of a procedure parameter/return or a global
//   (compile time and run time, macOS and Linux; the layout itself stays right). Reliable instead:
//   put the type after a u8 in a probe struct; the member's offset is the alignment.
// - Basic.align_forward(value, alignment) rounds up (any positive alignment); for powers of two,
//   (x + a - 1) & ~(a - 1) is the same. A misaligned value may also SPLIT a cache line (64 bytes on
//   Intel, 128 on Apple M-series) or a page (4 KiB on Linux x64, 16 KiB on macOS arm64): such
//   loads touch two lines/pages. Atomics on a split line are "split locks" on x86: never do that.
// - #align N works on struct members (raising the struct's alignment and size), globals and
//   locals. Allocators get no alignment argument (the Allocator_Proc has none): New(T) asks for
//   size_of(T) bytes and gets the heap's alignment (16 bytes), temp gives 8, Flat_Pool/Pool give
//   their `alignment` field (8 by default). For more, NewArray(n, T, alignment = A): it allocates
//   A extra bytes and rounds data up; free the second return value (unaligned_base), not data.
// EXPECT: size/alignment: u8 1/1 u16 2/2 u32 4/4 u64 8/8 float32 4/4 float64 8/8 bool 1/1 *void 8/8
// EXPECT: size/alignment: string 16/8 [] int 16/8 [..] int 40/8 Any 16/8 [3] u16 6/2
// EXPECT: structs: Mixed 24/8, Reordered 16/8, Vec3 12/4, Line_Owner 64/64 (hot@0 cold@8)
// EXPECT: type_info(T).alignment: Point_Twin 4, Point -1 (Point is in point_sum's signature); probe: 4 and 4
// EXPECT: align_forward: 13 -> 16 (by 8), 16 -> 16 (by 8), 100 -> 128 (by 64), 10 -> 12 (by 3); mask form agrees: true
// EXPECT: u64 at offset    0: aligned true,  splits a 64 B line false, a 128 B line false, a 4 KiB page false
// EXPECT: u64 at offset    4: aligned false, splits a 64 B line false, a 128 B line false, a 4 KiB page false
// EXPECT: u64 at offset   60: aligned false, splits a 64 B line true, a 128 B line false, a 4 KiB page false
// EXPECT: u64 at offset  124: aligned false, splits a 64 B line true, a 128 B line true, a 4 KiB page false
// EXPECT: u64 at offset 4092: aligned false, splits a 64 B line true, a 128 B line true, a 4 KiB page true
// EXPECT: #align on variables: local [100] u8 #align 64: true, global [16] u8 #align 4096: true
// EXPECT: alloc(1..100) results are 16-byte aligned: true
// EXPECT: New(Line_Owner) asked its allocator for 64 bytes, nothing about alignment: true
// EXPECT: NewArray(5, u8, alignment = 4096): data aligned true, 0 <= data - unaligned_base < 4096: true
// EXPECT: temp: after talloc(3), the next talloc starts 8 bytes later: true
// EXPECT: Flat_Pool with alignment = 64: three 24-byte gets are 64 bytes apart: true
// EXPECT: #no_padding {u8, u64, u8}: size 17, alignment 8; in an array, element 1's u64 is at byte 25
// EXPECT-CONTAINS: page size on this machine:
#import "Basic";
#import "Flat_Pool";
#import "POSIX";

Align_Probe :: struct (T: Type) { first: u8; value: T; }
align_of :: ($T: Type) -> s64 { return type_info(Align_Probe(T)).members[1].offset_in_bytes; }

Mixed      :: struct { a: u8; b: u64; c: u8; }
Reordered  :: struct { b: u64; a: u8; c: u8; }
Vec3       :: struct { x, y, z: float32; }
Line_Owner :: struct { hot: s64 #align 64; cold: [3] s64; }
Packed     :: struct { a: u8; b: u64; c: u8; } #no_padding

Point      :: struct { x, y: s32; }      // used in a signature below
Point_Twin :: struct { x, y: s32; }      // same members, never in a signature

point_sum :: (points: [] Point) -> s64 {
    total: s64;
    for points total += it.x + it.y;
    return total;
}

page_buffer: [16] u8 #align 4096;

sa :: ($T: Type) -> string { return tprint("%/%", size_of(T), align_of(T)); }

offset_of :: ($T: Type, name: string) -> s64 {
    for type_info(T).members if it.name == name return it.offset_in_bytes;
    return -1;
}

is_aligned :: (address: u64, alignment: u64) -> bool { return address % alignment == 0; }
splits     :: (address: u64, size: u64, boundary: u64) -> bool { return address / boundary != (address + size - 1) / boundary; }

Recorder :: struct { last_size: s64; }

recording_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    if mode == .ALLOCATE { (cast(*Recorder) data).last_size = size; }
    return context.default_allocator.proc(mode, size, old_size, old_memory, null);
}

main :: () {
    print("size/alignment: u8 % u16 % u32 % u64 % float32 % float64 % bool % *void %\n",
        sa(u8), sa(u16), sa(u32), sa(u64), sa(float32), sa(float64), sa(bool), sa(*void));
    print("size/alignment: string % [] int % [..] int % Any % [3] u16 %\n", sa(string), sa([] int), sa([..] int), sa(Any), sa([3] u16));
    print("structs: Mixed %, Reordered %, Vec3 %, Line_Owner % (hot@% cold@%)\n", sa(Mixed), sa(Reordered), sa(Vec3), sa(Line_Owner),
        offset_of(Line_Owner, "hot"), offset_of(Line_Owner, "cold"));
    print("type_info(T).alignment: Point_Twin %, Point % (Point is in point_sum's signature); probe: % and %\n",
        type_info(Point_Twin).alignment, type_info(Point).alignment, align_of(Point_Twin), align_of(Point));
    assert(point_sum(.[.{1, 2}]) == 3);

    mask_ok := true;
    for value: 0..300 for shift: 0..7 {
        a := 1 << shift;
        if align_forward(value, a) != (value + a - 1) & ~(a - 1) mask_ok = false;
    }
    print("align_forward: 13 -> % (by 8), 16 -> % (by 8), 100 -> % (by 64), 10 -> % (by 3); mask form agrees: %\n",
        align_forward(13, 8), align_forward(16, 8), align_forward(100, 64), align_forward(10, 3), mask_ok);

    buffer, base := NewArray(8192, u8, alignment = 4096);   // starts on a page boundary
    for offset: int.[0, 4, 60, 124, 4092] {
        address := cast(u64) (buffer.data + offset);
        print("u64 at offset %: aligned % splits a 64 B line %, a 128 B line %, a 4 KiB page %\n",
            formatInt(offset, minimum_digits = 4, padding = #char " "), ifx is_aligned(address, 8) then "true, " else "false,",
            splits(address, 8, 64), splits(address, 8, 128), splits(address, 8, 4096));
    }

    local_buffer: [100] u8 #align 64;
    print("#align on variables: local [100] u8 #align 64: %, global [16] u8 #align 4096: %\n",
        is_aligned(cast(u64) local_buffer.data, 64), is_aligned(cast(u64) page_buffer.data, 4096));

    all16 := true;
    for size: 1..100 {
        p := alloc(size);
        if !is_aligned(cast(u64) p, 16) all16 = false;
        free(p);
    }
    print("alloc(1..100) results are 16-byte aligned: %\n", all16);

    recorder: Recorder;
    owner := New(Line_Owner,, Allocator.{recording_allocator_proc, *recorder});
    print("New(Line_Owner) asked its allocator for % bytes, nothing about alignment: %\n", recorder.last_size, recorder.last_size == size_of(Line_Owner));
    free(owner);

    distance := buffer.data - cast(*u8) base;
    print("NewArray(5, u8, alignment = 4096): data aligned %, 0 <= data - unaligned_base < 4096: %\n",
        is_aligned(cast(u64) NewArray(5, u8, alignment = 4096).data, 4096), distance >= 0 && distance < 4096);
    free(base);

    t1 := cast(*u8) talloc(3);
    t2 := cast(*u8) talloc(8);
    print("temp: after talloc(3), the next talloc starts 8 bytes later: %\n", t2 - t1 == 8);

    pool: Flat_Pool;
    pool.alignment = 64;                     // before the first get; must be a power of two
    g1 := cast(*u8) get(*pool, 24);
    g2 := cast(*u8) get(*pool, 24);
    g3 := cast(*u8) get(*pool, 24);
    print("Flat_Pool with alignment = 64: three 24-byte gets are 64 bytes apart: %\n", g2 - g1 == 64 && g3 - g2 == 64 && is_aligned(cast(u64) g1, 64));
    fini(*pool);

    packed: [2] Packed;
    print("#no_padding {u8, u64, u8}: size %, alignment %; in an array, element 1's u64 is at byte %\n",
        size_of(Packed), align_of(Packed), cast(*u8) *packed[1].b - cast(*u8) packed.data);

    print("page size on this machine: % bytes\n", getpagesize(), to_standard_error = true);
}
