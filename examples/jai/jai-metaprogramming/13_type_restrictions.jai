// Type restrictions on polymorph variables:
//   $T/Base            T must be Base or a struct that has `#as using` Base ("subclass")
//   $T/interface Shape T must have members with the same names and types as Shape (duck typing;
//                      the struct is only a list of required members)
//   $T/.[string, u8]   T must be one of the listed types (a constant array of types; overloads
//                      resolve through implicit conversions since 0.2.021). Other types fail with
//                      "did not match any of the possible target types of a type restriction".
// Inside the body T is the full argument type, so #if can specialize per type.
// EXPECT: Player Ada at 1,2
// EXPECT: Monster Grue at 5,5 (hp 30)
// EXPECT: area of Rect = 12
// EXPECT: area of Labeled_Rect = 2
// EXPECT: type list: "text" is a string; 65 is a byte

#import "Basic";

Entity  :: struct { name: string; x, y: int; }
Player  :: struct { #as using base: Entity; score: int; }
Monster :: struct { #as using base: Entity; hp: int; }

describe :: (e: $T/Entity) {
    #if T == Monster  print("Monster % at %,% (hp %)\n", e.name, e.x, e.y, e.hp);
    else              print("% % at %,%\n", T, e.name, e.x, e.y);
}

Has_Size     :: struct { w, h: float; }      // only used as an interface
Rect         :: struct { w, h: float; }
Labeled_Rect :: struct { label: string; h: float; color: u32; w: float; }   // order does not matter

area :: (s: $T/interface Has_Size) -> float { return s.w * s.h; }

one_of :: (x: $T/.[string, u8]) -> string {
    #if T == string  return tprint("\"%\" is a string", x);
    else             return tprint("% is a byte", x);
}

main :: () {
    p: Player;  p.name = "Ada";  p.x, p.y = 1, 2;
    m: Monster; m.name = "Grue"; m.x, m.y = 5, 5; m.hp = 30;
    describe(p);
    describe(m);
    print("area of Rect = %\n", area(Rect.{3, 4}));
    print("area of Labeled_Rect = %\n", area(Labeled_Rect.{label = "door", w = 1, h = 2}));
    print("type list: %; %\n", one_of("text"), one_of(cast(u8) 65));
}
