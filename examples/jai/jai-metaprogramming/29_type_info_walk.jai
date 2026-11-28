// type_info(T) returns the most specific *Type_Info_* struct for T (here *Type_Info_Struct); the
// same data exists at run time, which is what print() uses. Notes: `@Name` after a member's
// semicolon, after a struct's `struct`, `@"with spaces"` for free text. Constants show up as
// members with the CONSTANT flag and no offset. Enums expose names and values.
// EXPECT: Player (size 40) notes ["Saveable"]
// EXPECT:   name: string @ 0 ["Key"]
// EXPECT:   hp: s32 @ 16 []
// EXPECT:   position: [3] float32 @ 20 []
// EXPECT:   secret: s64 @ 32 ["NoSave", "shown in the editor as Secret"]
// EXPECT:   MAX_HP: s64 (constant) []
// EXPECT: Mood names ["CALM", "ANGRY", "SLEEPY"] values [1, 5, 6]
// EXPECT: Perms is enum_flags: true; READ | EXEC prints as READ | EXEC
// EXPECT: Any holding s64: 42 / string: hi / struct: Player

#import "Basic";

Player :: struct @Saveable {
    name: string;      @Key
    hp: s32 = 100;
    position: [3] float;
    secret: int;       @NoSave @"shown in the editor as Secret"
    MAX_HP :: 200;
}

Mood  :: enum u8 { CALM :: 1; ANGRY :: 5; SLEEPY; }      // SLEEPY continues from 5
Perms :: enum_flags u8 { READ; WRITE; EXEC; }

describe :: ($T: Type) {
    info := type_info(T);              // *Type_Info_Struct, because T is a struct
    print("% (size %) notes %\n", info.name, size_of(T), info.notes);
    for m: info.members {
        if m.flags & .CONSTANT  print("  %: % (constant) %\n", m.name, type_to_string(m.type), m.notes);
        else                    print("  %: % @ % %\n", m.name, type_to_string(m.type), m.offset_in_bytes, m.notes);
    }
}

any_to_text :: (a: Any) -> string {
    if a.type.type == {
      case .INTEGER; return tprint("s64: %", (cast(*s64) a.value_pointer).*);
      case .STRING;  return tprint("string: %", (cast(*string) a.value_pointer).*);
      case .STRUCT;  return tprint("struct: %", (cast(*Type_Info_Struct) a.type).name);
    }
    return "other";
}

main :: () {
    describe(Player);
    print("Mood names % values %\n", enum_names(Mood), enum_values_as_s64(Mood));
    flags := type_info(Perms).enum_type_flags;
    print("Perms is enum_flags: %; READ | EXEC prints as %\n", (flags & .FLAGS) != 0, Perms.READ | .EXEC);
    n := 42; s := "hi"; p: Player;
    print("Any holding % / % / %\n", any_to_text(n), any_to_text(s), any_to_text(p));
}
