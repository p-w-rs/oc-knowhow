// The compile-time counterpart of 30: a polymorphic procedure whose body is GENERATED from
// type_info(T) with #insert, once per type. At run time there is no type walk, just straight
// field-by-field code (inspect it in .build/.added_strings_w2.jai). Nested structs recurse
// through the same polymorphic procedure, so each struct type gets its own generated writer.
// Escaping: inside the generated string, `\%` is a literal percent sign for print (not `%%`).
// EXPECT-COMPILE: [compile time] generated write_fields for Player
// EXPECT-COMPILE: [compile time] generated write_fields for Vec2
// EXPECT: Player{name=Ada, hp=100, pos=Vec2{x=1, y=2.5}}

#import "Basic";

write_fields :: (sb: *String_Builder, value: $T) {
    #insert -> string {
        print("[compile time] generated write_fields for %\n", T);
        info := type_info(T);
        code: String_Builder;
        print_to_builder(*code, "append(sb, \"%{\");\n", info.name);
        first := true;
        for m: info.members {
            if m.flags & .CONSTANT  continue;
            if array_find(m.notes, "NoSave")  continue;
            if !first append(*code, "append(sb, \", \");\n");
            first = false;
            if m.type.type == .STRUCT
                print_to_builder(*code, "append(sb, \"%1=\"); write_fields(sb, value.%1);\n", m.name);
            else
                print_to_builder(*code, "print_to_builder(sb, \"%1=\%\", value.%1);\n", m.name);
        }
        append(*code, "append(sb, \"}\");\n");
        return builder_to_string(*code);
    }
}

Vec2   :: struct { x, y: float; }
Player :: struct {
    name  := "Ada";
    hp    := 100;
    pos   := Vec2.{1, 2.5};
    cache: [64] u8;    @NoSave
}

main :: () {
    sb: String_Builder;
    write_fields(*sb, Player.{});
    print("%\n", builder_to_string(*sb));
}
