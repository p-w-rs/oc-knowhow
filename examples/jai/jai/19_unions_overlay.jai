// EXPECT: union: 1.0 has bits 3f800000, size 4
// EXPECT: #overlay: channels [68, 51, 34, 17], size 4
// EXPECT: tagged union: {TEXT, hello}, tag TEXT, size 24
// EXPECT: switch on the tag: text 'hello'
// Plain `union { ... }` puts every member at offset 0. `#overlay (member) name: T;` inside a struct
// places a second view on top of an existing member; the bindings generator now prefers #overlay
// over untagged unions (0.2.030), so use it for reinterpreting bits.
// Tagged unions (since 0.2.023; field bindings since 0.2.025): `union tag: Enum { .A ,, a: T; ... }`.
// They have no checked access yet: you switch on the tag yourself.
// (Little-endian byte order is assumed for the #overlay line; both test machines are little-endian.)

#import "Basic";

Bits :: union { f: float32; u: u32; }

Pixel :: struct {
    rgba: u32;
    #overlay (rgba) channels: [4] u8;
}

Kind :: enum u8 { NUMBER; TEXT; }
Value :: union kind: Kind {
    .NUMBER ,, n: int;
    .TEXT   ,, s: string;
}

describe :: (v: Value) -> string {
    if v.kind == {
        case .NUMBER; return tprint("number %", v.n);
        case .TEXT;   return tprint("text '%'", v.s);
    }
    return "?";
}

main :: () {
    b: Bits;
    b.f = 1.0;
    print("union: 1.0 has bits %, size %\n", formatInt(b.u, base = 16), size_of(Bits));

    p: Pixel;
    p.rgba = 0x11223344;
    print("#overlay: channels %, size %\n", p.channels, size_of(Pixel));

    v: Value;
    v.kind = .TEXT;
    v.s = "hello";
    print("tagged union: %, tag %, size %\n", v, v.kind, size_of(Value));
    print("switch on the tag: %\n", describe(v));
}
