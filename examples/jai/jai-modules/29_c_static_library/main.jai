#import "Basic";

// The compiler resolves #library at compile time: plain #library "lib/geo" would
// look for lib/geo.dylib / lib/geo.so and fail ("Dynamic library load failed").
// ,no_dll says "there is only a static library": lib/geo.a goes on the link line
// and symbol typos show up as linker errors.
geo :: #library,no_dll "lib/geo";

// C types map to sized Jai types: int32_t = s32, size_t = u64 (64-bit targets),
// float = float32, char* = *u8. A Jai struct matches a C struct with the same members.
Vec2 :: struct { x, y: float32; }
Record :: struct { tag: u8; value: s32; port: u16; }
Packed_Record :: struct { tag: u8; value: s32 #align 1; port: u16 #align 1; }   // what __attribute__((packed)) means
No_Padding_Record :: struct { tag: u8; value: s32; port: u16; } #no_padding      // NOT the same as packed

Reducer :: #type (acc: s32, value: s32, user: *void) -> s32 #c_call;

geo_add        :: (a: s32, b: s32) -> s32 #foreign geo;
geo_scale      :: (v: Vec2, k: float32) -> Vec2 #foreign geo;
geo_length_sq  :: (v: *Vec2) -> float32 #foreign geo;
geo_count_char :: (s: *u8, c: u8) -> u64 #foreign geo;
geo_sum        :: (items: *s32, n: u64) -> s64 #foreign geo;
geo_reduce     :: (items: *s32, n: u64, f: Reducer, user: *void) -> s32 #foreign geo;
geo_version    :: () -> *u8 #foreign geo;
geo_layout     :: (out: *[8] u64) #foreign geo;      // C array parameter: pass a pointer
geo_record_sum :: (r: Record) -> s32 #foreign geo;
geo_packed_sum :: (r: Packed_Record) -> s32 #foreign geo;
geo_calls: s32 #elsewhere geo;                       // a C global variable

// A callback C can call: #c_call (C convention, no implicit context).
max_reducer :: (acc: s32, value: s32, user: *void) -> s32 #c_call {
    calls := cast(*int) user;
    calls.* += 1;
    if calls.* == 1  push_context { print("  first callback from C: value %\n", value); }  // print needs a context
    return ifx value > acc then value else acc;
}

offsets :: ($T: Type) -> (value: s64, port: s64) {
    value, port: s64;
    for type_info(T).members {
        if it.name == "value"  value = it.offset_in_bytes;
        if it.name == "port"   port  = it.offset_in_bytes;
    }
    return value, port;
}

main :: () {
    print("add: %\n", geo_add(40, 2));
    v := geo_scale(.{3, 4}, 2);
    print("scale: %\n", v);
    print("length_sq: %\n", geo_length_sq(*v));
    word := copy_string("banana");                   // a Jai string is not NUL-terminated:
    print("count of 'a' in banana: %\n", geo_count_char(temp_c_string(word), #char "a"));
    items := s32.[5, 9, 2, 7];
    print("sum: %\n", geo_sum(items.data, xx items.count));
    calls := 0;
    best := geo_reduce(items.data, xx items.count, max_reducer, *calls);
    print("max via callback: % (% callbacks)\n", best, calls);
    print("version: %\n", to_string(geo_version()));   // borrow a C string as a Jai string (no copy)
    print("C global geo_calls: %\n", geo_calls);

    c: [8] u64;
    geo_layout(*c);
    rv, rp := offsets(Record);
    pv, pp := offsets(Packed_Record);
    nv, np := offsets(No_Padding_Record);
    print("C layout Record: value@% port@% size % / Jai: value@% port@% size %\n", c[0], c[1], c[2], rv, rp, size_of(Record));
    print("C layout Packed_Record: value@% port@% size % / Jai: value@% port@% size %\n", c[3], c[4], c[5], pv, pp, size_of(Packed_Record));
    print("#no_padding alone: value@% port@% size % (only the trailing padding goes)\n", nv, np, size_of(No_Padding_Record));
    print("record sums: % %\n", geo_record_sum(.{7, 3000, 0}), geo_packed_sum(.{7, 3000, 0}));
}
