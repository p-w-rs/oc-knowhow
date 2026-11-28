// EXPECT: integer of 8 bytes
// EXPECT: integer of 1 bytes
// EXPECT: float of 4 bytes
// EXPECT: string "hi"
// EXPECT: struct Point: x INTEGER @0, y INTEGER @4, label STRING @8
// EXPECT: other: BOOL
// EXPECT: Type values: Point, 24 bytes; int == s64: true; 1.0 is float64: false
// EXPECT: type_info(Point) has type *Type_Info_Struct
// EXPECT: Any points at its value: 5 then 6
// `Any` is { type: *Type_Info; value_pointer: *void; } and accepts any value (print's ..Any is how
// print knows argument types). The Any points AT the original storage: it does not copy it.
// `Type` is a first-class value; `type_info(T)` returns the most specific *Type_Info_* struct,
// so you can walk members, enum names, array element types, etc. at runtime.

#import "Basic";

Point :: struct { x: s32; y: s32; label: string; }

show :: (v: Any) {
    if v.type.type == {
        case .INTEGER; print("integer of % bytes\n", v.type.runtime_size);
        case .FLOAT;   print("float of % bytes\n", v.type.runtime_size);
        case .STRING;  print("string \"%\"\n", (cast(*string) v.value_pointer).*);
        case .STRUCT;
            info := cast(*Type_Info_Struct) v.type;
            print("struct %:", info.name);
            for info.members {
                if it_index  print(",");
                print(" % % @%", it.name, it.type.type, it.offset_in_bytes);
            }
            print("\n");
        case;          print("other: %\n", v.type.type);
    }
}

main :: () {
    show(42);
    show(cast(u8) 1);
    show(2.5);
    show("hi");
    show(Point.{1, 2, "p"});
    show(true);

    t: Type = Point;
    print("Type values: %, % bytes; int == s64: %; 1.0 is float64: %\n",
          t, size_of(Point), int == s64, type_of(1.0) == float64);
    print("type_info(Point) has type %\n", type_of(type_info(Point)));

    n := 5;
    a: Any = n;
    print("Any points at its value: % ", a);
    n += 1;
    print("then %\n", a);
}
