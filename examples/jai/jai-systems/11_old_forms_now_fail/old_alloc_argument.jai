// Before 0.1.080 alloc, New, copy_string... took an allocator argument. Now: alloc(64,, temp).
#import "Basic";
main :: () {
    p := alloc(64, temp);
}
