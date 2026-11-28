// EXPECT: color GREEN = 1, size 8 bytes; u8-backed: 1 byte
// EXPECT: explicit values: LOW=1 MID=2 HIGH=10 HIGHER=11
// EXPECT: unary dot: f(.BLUE) -> BLUE; default arg -> RED
// EXPECT: names ["LOW", "MID", "HIGH", "HIGHER"] range 1..11
// EXPECT: flags READ | EXEC = 5; has WRITE: false
// EXPECT: after |= .WRITE and &= ~.READ: WRITE | EXEC
// EXPECT: Level is specified: true
// enum: named integer constants (s64 by default: `enum u8 {...}` picks the storage type).
// Members auto-increment from 0 or from the last explicit `NAME :: value;`.
// `.NAME` (unary dot) works wherever the enum type is known from context.
// enum_flags: members get 1, 2, 4, 8 ...; combine with | and remove with & ~.
// #specified: every member must have an explicit value (a promise that values are stable for serialization).

#import "Basic";

Color :: enum { RED; GREEN; BLUE; }
Small :: enum u8 { A; B; }
Level :: enum u16 #specified { LOW :: 1; MID :: 2; HIGH :: 10; HIGHER :: 11; }
Perm  :: enum_flags u8 { READ; WRITE; EXEC; }

show :: (c: Color) -> Color { return c; }
pick :: (c: Color = .RED) -> Color { return c; }

main :: () {
    c := Color.GREEN;
    print("color % = %, size % bytes; u8-backed: % byte\n", c, cast(int) c, size_of(Color), size_of(Small));

    print("explicit values: LOW=% MID=% HIGH=% HIGHER=%\n",
          cast(int) Level.LOW, cast(int) Level.MID, cast(int) Level.HIGH, cast(int) Level.HIGHER);

    print("unary dot: f(.BLUE) -> %; default arg -> %\n", show(.BLUE), pick());

    low, high := enum_range(Level);
    print("names % range %..%\n", enum_names(Level), low, high);

    p := Perm.READ | .EXEC;
    print("flags % = %; has WRITE: %\n", p, cast(u8) p, (p & .WRITE) != 0);
    p |= .WRITE;
    p &= ~.READ;
    print("after |= .WRITE and &= ~.READ: %\n", p);

    info := type_info(Level);
    print("Level is specified: %\n", (info.enum_type_flags & .SPECIFIED) != 0);
}
