// The point of #type,distinct: a raw u32 cannot be passed where an Entity_Handle is expected.
// Fix by converting on purpose: slot_of(cast(Entity_Handle) raw) (or xx raw).
// EXPECT-COMPILE-ERROR: Type mismatch. Type wanted: Entity_Handle; type given: u32.

#import "Basic";

Entity_Handle :: #type,distinct u32;
slot_of :: (h: Entity_Handle) -> u32 { return cast(u32) h; }

main :: () {
    raw: u32 = 12;
    print("%\n", slot_of(raw));
}
