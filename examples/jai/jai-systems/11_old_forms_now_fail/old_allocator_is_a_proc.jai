// Since 0.0.096 an Allocator is a struct {proc, data}, not a procedure.
// Now: context.allocator = .{my_allocator_proc, my_data};  (or push_allocator(my_allocator_proc, my_data))
#import "Basic";
my_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old: *void, data: *void) -> *void { return null; }
main :: () { context.allocator = my_allocator_proc; }
