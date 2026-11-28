// EXPECT: positional {1, 2}, dot-less {3, 4}, dotted {5, 6}, named {0, 9}
// EXPECT: defaults: {"unnamed", {0, 5}, 100, ["", ""]}
// EXPECT: literal with paths: {"goblin", {0, 5}, 7, ["", "green"]}
// EXPECT: returned: {2, 4} and default {0, 0}
// EXPECT: copy is independent: original 3, copy 99
// EXPECT: through a pointer: hp 90
// EXPECT: sizes: Vec2 8, Entity 64
// Struct members are laid out in declaration order (C-like padding, no reordering).
// Defaults are written like declarations; the body may also override a nested member's default.
// Literals: Type.{...} anywhere; {...} (or the older .{...}) when the type is known from context.
// Positional literals must give every member; named ones may give any subset.
// Assignment copies bytes; there are no constructors, destructors or copy operators.

#import "Basic";

Vec2 :: struct { x, y: float; }

Entity :: struct {
    name  := "unnamed";
    pos:  Vec2;
    pos.y = 5;                 // default for a member of a member
    hp    := 100;
    tags: [2] string;
}

doubled :: (v: Vec2) -> Vec2 { return {v.x * 2, v.y * 2}; }   // return type gives the literal its type
origin  :: () -> Vec2 { return {}; }                            // {} = all defaults

main :: () {
    a := Vec2.{1, 2};
    b: Vec2 = {3, 4};
    c: Vec2 = .{5, 6};
    d := Vec2.{y = 9};
    print("positional %, dot-less %, dotted %, named %\n", a, b, c, d);

    e: Entity;
    print("defaults: %\n", e);
    g := Entity.{name = "goblin", hp = 7, tags[1] = "green"};
    print("literal with paths: %\n", g);

    print("returned: % and default %\n", doubled(a), origin());

    original := Entity.{hp = 3};
    copy := original;
    copy.hp = 99;
    print("copy is independent: original %, copy %\n", original.hp, copy.hp);

    p := *g;
    p.hp += 83;                // '.' works through pointers: no '->'
    print("through a pointer: hp %\n", g.hp);

    print("sizes: Vec2 %, Entity %\n", size_of(Vec2), size_of(Entity));
}
