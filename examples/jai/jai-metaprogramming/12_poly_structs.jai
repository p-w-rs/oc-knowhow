// Polymorphic structs take compile-time parameters (types or values; the $ is optional there) and
// may have defaults. A fully specified instance is an ordinary type. In a procedure header the bare
// name matches ANY instance, and the parameters are reachable as members (`r.Capacity`, `r.T`).
// #this names the enclosing struct (or procedure) without repeating its parameters.
// Reflection: an instance's Type_Info_Struct lists its specified_parameters (values live in
// constant_storage); polymorph_source_struct is the generic struct with its unbound `parameters`
// (both since 0.2.012). Type_Info_Struct.alignment (0.2.030) is -1 for instances of polymorphic
// structs in 0.2.032, so compute alignment yourself there.
// EXPECT: Small_Buffer(T=s64, Capacity=4) size_of = 48
// EXPECT: [10, 20, 30] full=false
// EXPECT: default instance: T=float32 Capacity=8
// EXPECT: same type from named args: true
// EXPECT: self pointer type is *Small_Buffer(T=s64, Capacity=4): true
// EXPECT: specified parameters: T Capacity; Capacity read from type info = 4
// EXPECT: generic source Small_Buffer has 2 parameters
// EXPECT: alignment: plain struct 8, polymorphic instance -1

#import "Basic";

Plain :: struct { a: u8; b: float64; }

parameter_value :: (info: *Type_Info_Struct, name: string) -> s64 {
    for info.specified_parameters {
        if it.name != name || it.type.type != .INTEGER continue;
        return (cast(*s64) (info.constant_storage.data + it.offset_into_constant_storage)).*;
    }
    return -1;
}

Small_Buffer :: struct (T: Type = float, Capacity: int = 8) {
    items: [Capacity] T;
    count: int;
    self:  *#this;               // pointer to this exact instance type
}

push :: (b: *Small_Buffer, value: b.T) -> bool {     // matches every Small_Buffer(...)
    if b.count == b.Capacity return false;
    b.items[b.count] = value;
    b.count += 1;
    return true;
}

view :: (b: Small_Buffer) -> [] b.T {
    result: [] b.T;
    result.data  = b.items.data;
    result.count = b.count;
    return result;
}

main :: () {
    ints: Small_Buffer(int, 4);
    print("Small_Buffer(T=%, Capacity=%) size_of = %\n", ints.T, ints.Capacity, size_of(type_of(ints)));
    push(*ints, 10); push(*ints, 20); push(*ints, 30);
    print("% full=%\n", view(ints), ints.count == ints.Capacity);

    d: Small_Buffer;                         // all parameters defaulted
    print("default instance: T=% Capacity=%\n", d.T, d.Capacity);

    named: Small_Buffer(Capacity = 4, T = int);
    print("same type from named args: %\n", type_of(named) == type_of(ints));
    print("self pointer type is *Small_Buffer(T=s64, Capacity=4): %\n", type_of(ints.self) == *type_of(ints));

    info := type_info(Small_Buffer(int, 4));
    print("specified parameters:");
    for info.specified_parameters print(" %", it.name);
    print("; Capacity read from type info = %\n", parameter_value(info, "Capacity"));
    source := info.polymorph_source_struct;
    print("generic source % has % parameters\n", source.name, source.parameters.count);
    print("alignment: plain struct %, polymorphic instance %\n", type_info(Plain).alignment, info.alignment);
}
