// Old code (2020-2022): #foreign_library / #foreign_system_library. Renamed to
// #library / #system_library in 0.1.049, old names removed in 0.2.002.
// Current forms:
//     libc :: #library,system "libc";    (preferred spelling since 0.1.084)
//     libc :: #system_library "libc";    (still accepted, no warning, 0.2.032)
//     mine :: #library "lib/mine";       (path relative to this file, no extension)
// EXPECT-COMPILE-ERROR: Invalid toplevel directive name 'foreign_system_library'

libc :: #foreign_system_library "libc";
c_abs :: (x: s32) -> s32 #foreign libc "abs";

main :: () { c_abs(-3); }
