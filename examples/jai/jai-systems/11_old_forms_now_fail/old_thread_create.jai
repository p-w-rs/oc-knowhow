// Removed in 0.1.071: declare a Thread yourself, thread_init(*t, proc), thread_start, thread_deinit.
#import "Basic";
#import "Thread";
work :: (t: *Thread) -> s64 { return 0; }
main :: () { t := thread_create(work); }
