// A #modify that returns false (with a reason) rejects the polymorph at the call site.
// This one validates struct parameters against each other: higher-order checks in plain code.
// EXPECT-COMPILE-ERROR: #modify returned false: Grid needs Width >= Height (got 2 x 8)
// EXPECT-COMPILE-ERROR: While attempting a polymorph here.

#import "Basic";

Grid :: struct (Width: int, Height: int)
#modify {
    return Width >= Height, tprint("Grid needs Width >= Height (got % x %)", Width, Height);
}
{
    cells: [Width * Height] u8;
}

main :: () {
    ok: Grid(8, 2);
    bad: Grid(2, 8);
}
