// Data layout control: fields are laid out in declaration order with natural alignment, so
// ordering matters (largest first avoids holes); #align N on a member or a variable aligns it
// (e.g. per-thread counters on separate cache lines: a line is 64 bytes on x86-64 but 128 on
// Apple M-series, so use 128 for code that runs there; heap arrays need NewArray(..., alignment = N),
// because New/NewArray alone ignore #align: see examples 48 and 49).
// Check layouts with size_of and the member offsets in type_info(T).members.
//
// PITFALL (0.2.032): #no_padding does NOT pack the members. For {u8, u64, u8} they stay at
// offsets 0, 8, 16 (in type_info and in memory); only the TRAILING padding goes (size_of 17
// instead of 24). Arrays then use a stride of 17, so from the second element on, the u64 sits
// at an odd address (arr[1].b at byte 25): misaligned, and still not a packed wire layout.
// The modules use #no_padding only on structs whose members are already packed (file headers).
// For packed formats order the fields so no padding is needed, or serialize byte by byte.
// EXPECT: Mixed     size 24 (a@0 b@8 c@16)
// EXPECT: Reordered size 16 (b@0 a@8 c@9)
// EXPECT: Packed    size 17 (#no_padding: a@0 b@8 c@16)
// EXPECT: [3] Packed: stride 17, arr[1].b at byte 25 (8-byte aligned: false)
// EXPECT: Header    size 8 (#no_padding on an already packed struct is fine: tag@0 version@4 flags@6)
// EXPECT: Padded_Counter size 64, array of 8 = 512 bytes
// EXPECT: local #align 64 variable is aligned: true
#import "Basic";

Mixed     :: struct { a: u8; b: u64; c: u8; }
Reordered :: struct { b: u64; a: u8; c: u8; }
Packed    :: struct { a: u8; b: u64; c: u8; } #no_padding
Header    :: struct { tag: u32; version: u16; flags: u16; } #no_padding

Padded_Counter :: struct {
    value: int #align 64;      // each counter starts a new 64-byte cache line
}

offsets :: ($T: Type) -> string {
    builder: String_Builder;
    for type_info(T).members {
        if it_index print(*builder, " ");
        print(*builder, "%@%", it.name, it.offset_in_bytes);
    }
    return builder_to_string(*builder,, temp);
}

main :: () {
    print("Mixed     size % (%)\n", size_of(Mixed), offsets(Mixed));
    print("Reordered size % (%)\n", size_of(Reordered), offsets(Reordered));
    print("Packed    size % (#no_padding: %)\n", size_of(Packed), offsets(Packed));

    arr: [3] Packed #align 8;
    base := cast(*u8) arr.data;
    b1 := cast(*u8) *arr[1].b - base;
    print("[3] Packed: stride %, arr[1].b at byte % (8-byte aligned: %)\n",
        cast(*u8) *arr[1] - base, b1, b1 % 8 == 0);

    print("Header    size % (#no_padding on an already packed struct is fine: %)\n", size_of(Header), offsets(Header));

    counters: [8] Padded_Counter;
    print("Padded_Counter size %, array of 8 = % bytes\n", size_of(Padded_Counter), size_of(type_of(counters)));
    scratch: [256] u8 #align 64;
    print("local #align 64 variable is aligned: %\n", (cast(u64) scratch.data) % 64 == 0);
}
