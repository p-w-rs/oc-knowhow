// A procedure passed to C as a function pointer must be #c_call. Jai procedures
// normally take the context as a hidden parameter, so the types differ and the
// compiler refuses (it does not silently wrap the procedure).
// EXPECT-COMPILE-ERROR: Type mismatch: the procedure must use the C calling convention, but the given procedure is native.

libc :: #library,system "libc";
qsort :: (base: *void, count: u64, size: u64, compare: (a: *void, b: *void) -> s32 #c_call) #foreign libc;

by_value :: (a: *void, b: *void) -> s32 {          // missing #c_call
    return (cast(*s32) a).* - (cast(*s32) b).*;
}

main :: () {
    numbers := s32.[3, 1, 2];
    qsort(numbers.data, xx numbers.count, size_of(s32), by_value);
}
