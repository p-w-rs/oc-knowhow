// Target program for build.jai: a few procedures, one tagged with a custom @Legacy note.
#import "Basic";

Vec2 :: struct { x, y: float; }

length_squared :: (v: Vec2) -> float { return v.x * v.x + v.y * v.y; }

old_sum :: (a: int, b: int) -> int { return a + b; } @Legacy

new_sum :: (values: ..int) -> int {
    total := 0;
    for values total += it;
    return total;
}

main :: () {
    print("% %\n", old_sum(2, 3), new_sum(2, 3, 4));
    print("%\n", length_squared(.{3, 4}));
}
