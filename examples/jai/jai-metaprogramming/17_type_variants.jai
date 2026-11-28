// Type variants make new named types from existing ones:
//   #type,distinct X   no implicit conversion to or from X (literals still convert); use cast
//   #type,isa X        converts implicitly TOWARD X (pass it where X is wanted), not between siblings;
//                      a call taking X and returning X hands back the variant type
// Their type info is a Type_Info_Variant (tag .VARIANT) whose variant_of is the base type.
// Type values themselves: a zero-initialized `Type` is `void` and tests false (since 0.2.029),
// handy as "no type chosen yet" in metaprograms.
// EXPECT: handle 7 -> slot 7
// EXPECT: meters passed as float: 3
// EXPECT: position + position is Position: true
// EXPECT: tags: Entity_Handle=VARIANT Meters=VARIANT; Meters.variant_of = FLOAT
// EXPECT: unset Type = void, set: false; after assignment = Meters, set: true

#import "Basic";
#import "Math";

Entity_Handle :: #type,distinct u32;
Meters        :: #type,isa float;
Position      :: #type,isa Vector3;
Velocity      :: #type,isa Vector3;

slot_of :: (h: Entity_Handle) -> u32 { return cast(u32) h; }
halve   :: (x: float) -> float { return x / 2; }

main :: () {
    h: Entity_Handle = 7;               // a literal converts
    print("handle % -> slot %\n", h, slot_of(h));

    m: Meters = 6;
    print("meters passed as float: %\n", halve(m));

    a := Position.{1, 2, 3};
    b := Position.{1, 0, 0};
    sum := a + b;                       // Vector3 operator +, result re-tagged as Position
    print("position + position is Position: %\n", type_of(sum) == Position);

    info := cast(*Type_Info_Variant) type_info(Meters);
    print("tags: Entity_Handle=% Meters=%; Meters.variant_of = %\n",
          type_info(Entity_Handle).type, info.type, info.variant_of.type);

    chosen: Type;
    unset_text := tprint("unset Type = %, set: %", chosen, ifx chosen then true else false);
    chosen = Meters;
    print("%; after assignment = %, set: %\n", unset_text, chosen, ifx chosen then true else false);
}
