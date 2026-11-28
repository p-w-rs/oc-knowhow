// Removed in 0.2.029: the allocator is called temp (or temporary_allocator).
#import "Basic";
main :: () { p := alloc(8,, __temporary_allocator); }
