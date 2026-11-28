// Only types the program asks type_info() about (and what they reference) get run-time type info.
// To shrink it further for big structs:
//   struct #type_info_none                          members are hidden (print shows {})
//   struct #type_info_procedures_are_void_pointers  procedure members are described as *void
//   compiler_set_type_info_flags(T, flags)          the same, from a #run, for types you can't edit
// Also: #dump on a procedure prints its bytecode at compile time (to see what polymorphs became).
// EXPECT-COMPILE: Disassembly of 'squared'
// EXPECT: full members: 2, #type_info_none members: 0
// EXPECT: Callbacks.on_tick described as POINTER
// EXPECT: Third_Party members after compiler_set_type_info_flags: 0
// EXPECT: hidden still works: 3 + 4 = 7
// EXPECT: squared(9) = 81

#import "Basic";
#import "Compiler";

Visible :: struct { a: int; b: int; }
Hidden  :: struct #type_info_none { a: int; b: int; }

Callbacks :: struct #type_info_procedures_are_void_pointers {
    on_tick: (dt: float, frame: int) -> bool;
}

Third_Party :: struct { n: int; label: string; }      // pretend this lives in someone else's module
#run compiler_set_type_info_flags(Third_Party, .NO_TYPE_INFO);

squared :: (x: int) -> int #dump { return x * x; }

main :: () {
    print("full members: %, #type_info_none members: %\n",
          type_info(Visible).members.count, type_info(Hidden).members.count);
    print("Callbacks.on_tick described as %\n", type_info(Callbacks).members[0].type.type);
    print("Third_Party members after compiler_set_type_info_flags: %\n", type_info(Third_Party).members.count);
    h := Hidden.{3, 4};
    print("hidden still works: % + % = %\n", h.a, h.b, h.a + h.b);
    print("squared(9) = %\n", squared(9));
}
