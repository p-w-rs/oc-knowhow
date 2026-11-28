// A generic serializer driven by run-time type info: one procedure handles every type by walking
// Type_Info and member offsets. Flexible (works on types it has never seen, even through Any)
// but every call re-walks the type. Notes control it: members tagged @NoSave are skipped.
// Compare with 31_serializer_compile_time.jai, which generates the code per type instead.
// EXPECT: {"name": "Ada", "hp": 100, "pos": {"x": 1, "y": 2.5}, "mood": "ANGRY", "alive": true, "scores": [1, 2, 3]}

#import "Basic";

write_json :: (sb: *String_Builder, data: *void, info: *Type_Info) {
    if info.type == {
      case .INTEGER;
        if info.runtime_size == {
          case 1; print_to_builder(sb, "%", (cast(*s8)  data).*);
          case 2; print_to_builder(sb, "%", (cast(*s16) data).*);
          case 4; print_to_builder(sb, "%", (cast(*s32) data).*);
          case;   print_to_builder(sb, "%", (cast(*s64) data).*);
        }
      case .FLOAT;
        if info.runtime_size == 4  print_to_builder(sb, "%", (cast(*float32) data).*);
        else                       print_to_builder(sb, "%", (cast(*float64) data).*);
      case .BOOL;
        print_to_builder(sb, "%", (cast(*bool) data).*);
      case .STRING;
        print_to_builder(sb, "\"%\"", (cast(*string) data).*);
      case .ENUM;
        e := cast(*Type_Info_Enum) info;
        value := get_enum_value(data, e);
        for e.values if it == value { print_to_builder(sb, "\"%\"", e.names[it_index]); break; }
      case .ARRAY;
        a := cast(*Type_Info_Array) info;
        count, elements := get_array_count_and_data(data, a);
        append(sb, "[");
        for i: 0..count-1 {
            if i append(sb, ", ");
            write_json(sb, elements + i * a.element_type.runtime_size, a.element_type);
        }
        append(sb, "]");
      case .STRUCT;
        s := cast(*Type_Info_Struct) info;
        append(sb, "{");
        first := true;
        for m: s.members {
            if m.flags & .CONSTANT  continue;
            if array_find(m.notes, "NoSave")  continue;
            if !first append(sb, ", ");
            first = false;
            print_to_builder(sb, "\"%\": ", m.name);
            write_json(sb, data + m.offset_in_bytes, m.type);
        }
        append(sb, "}");
      case;
        print_to_builder(sb, "null");
    }
}

to_json :: (value: Any) -> string {
    sb: String_Builder;
    write_json(*sb, value.value_pointer, value.type);
    return builder_to_string(*sb);
}

Mood :: enum u8 { CALM; ANGRY; }
Vec2 :: struct { x, y: float; }
Player :: struct {
    name   := "Ada";
    hp: s32 = 100;
    pos    := Vec2.{1, 2.5};
    mood   := Mood.ANGRY;
    alive  := true;
    scores: [..] int;
    token  := 1234;   @NoSave
}

main :: () {
    p: Player;
    array_add(*p.scores, 1, 2, 3);
    print("%\n", to_json(p));
}

#import "Reflection";    // get_array_count_and_data, get_enum_value
