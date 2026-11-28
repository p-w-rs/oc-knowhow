// EXPECT: block using: x 1 y 10
// EXPECT: member access through using chain: hero at {1, 5} hp 100 score 3
// EXPECT: #as lets a Player be passed as an Entity: hero
// EXPECT: using an enum: SLOW
// EXPECT: using,only: w 1
// `using` pulls a struct's members (or an enum's names, or a module's names) into the current scope.
// On a struct member it makes the inner members reachable directly (e.player.hp instead of
// e.player.base.hp); adding #as also allows implicit conversion to that member's type
// (the "base struct" pattern; there is no inheritance or virtual dispatch).

#import "Basic";

V :: struct { x, y: int; }
bump :: (using v: *V) { x += 1; y += 10; }        // like a method: members are in scope

Vec2   :: struct { x, y: float; }
Entity :: struct { name := "unnamed"; pos: Vec2; hp := 100; }
Player :: struct {
    #as using base: Entity;    // Player converts to Entity; base's members are Player's members
    score: int;
}
entity_name :: (e: Entity) -> string { return e.name; }

Quat :: struct { x, y, z: float; w: float = 1; }
Mode :: enum { FAST; SLOW; }

main :: () {
    v: V;
    bump(*v);
    {
        using v;               // scoped: the names disappear at the closing brace
        print("block using: x % y %\n", x, y);
    }

    p: Player;
    p.name = "hero";  p.score = 3;  p.pos = .{1, 5};
    print("member access through using chain: % at % hp % score %\n", p.name, p.pos, p.hp, p.score);
    print("#as lets a Player be passed as an Entity: %\n", entity_name(p));

    using Mode;
    m := SLOW;                 // instead of Mode.SLOW or .SLOW
    print("using an enum: %\n", m);

    q: Quat;
    using,only(w) q;           // also: using,except(x, y) ...
    print("using,only: w %\n", w);
}
