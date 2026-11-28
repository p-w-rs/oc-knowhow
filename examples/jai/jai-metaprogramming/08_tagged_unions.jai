// Tagged unions (experimental, since 0.2.023; tag bindings `.TAG ,, field` since 0.2.025):
//     Shape :: union kind: Shape_Kind { .CIRCLE ,, radius: float; ... }
// The tag (an enum here) is the first member, and the fields are laid out after it. print shows
// {TAG, payload}. A literal gives exactly two values (tag, payload) or none. There are no
// unwrap or safety checks yet: reading the wrong field is not caught, so switch on the tag yourself.
// Metaprograms see Struct_Textual_Flags.UNION_IS_TAGGED and Type_Info_Struct.tagged_union_bindings
// (tag value -> member index). The syntax is still changing (the `,,` binding is called temporary),
// tagged unions cannot be returned from #run (see 03), and the old Tagged_Union module was removed
// in 0.2.025.
// EXPECT: s = {RECT, [3, 4]}, area = 12
// EXPECT: label = {LABEL, door}
// EXPECT: flags: UNION | UNION_IS_TAGGED, size_of(Shape) = 24
// EXPECT: members: kind@0 radius@4 size@4 text@8
// EXPECT: binding CIRCLE -> radius
// EXPECT: binding RECT -> size
// EXPECT: binding LABEL -> text
// EXPECT: payload field for LABEL found by reflection: text

#import "Basic";

Shape_Kind :: enum u8 { CIRCLE; RECT; LABEL; }

Shape :: union kind: Shape_Kind {
    .CIRCLE ,, radius: float;
    .RECT   ,, size: [2] float;
    .LABEL  ,, text: string;
}

area :: (s: Shape) -> float {
    if s.kind == {
      case .CIRCLE; return 3.14159 * s.radius * s.radius;
      case .RECT;   return s.size[0] * s.size[1];
    }
    return 0;
}

// Generic over any tagged union: which member belongs to a tag value?
payload_name :: ($U: Type, tag: s64) -> string {
    info := type_info(U);
    for info.tagged_union_bindings
        if it.constant_value == cast(u64) tag  return info.members[it.member_index].name;
    return "";
}

main :: () {
    s: Shape;
    s.kind = .RECT;
    s.size = .[3, 4];
    print("s = %, area = %\n", s, area(s));

    label: Shape = .{.LABEL, "door"};     // (tag, payload)
    print("label = %\n", label);

    info := type_info(Shape);
    print("flags: %, size_of(Shape) = %\n", info.textual_flags, size_of(Shape));
    print("members:");
    for info.members print(" %@%", it.name, it.offset_in_bytes);
    print("\n");
    for info.tagged_union_bindings
        print("binding % -> %\n", cast(Shape_Kind) it.constant_value, info.members[it.member_index].name);
    print("payload field for LABEL found by reflection: %\n", payload_name(Shape, xx Shape_Kind.LABEL));
}
