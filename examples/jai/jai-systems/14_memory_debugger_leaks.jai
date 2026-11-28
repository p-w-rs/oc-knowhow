// The memory debugger is a module parameter of Basic. It hooks alloc/free/realloc (not the
// allocators), records a stack trace per allocation and reports leaks grouped by call stack.
//   #import "Basic"()(MEMORY_DEBUGGER=true);
// Once is enough: these are program parameters, so plain #import "Basic" elsewhere (other files,
// other modules) gets the same Basic; a second import WITH parameters is a compile error
// ("Cannot supply program parameters for the same module twice").
// - report_memory_leaks() prints to stdout; this_allocation_is_not_a_leak(p) excludes
//   intentional globals. Temporary storage, Pool and Flat_Pool allocations are not tracked.
// - Needs stack traces (on by default, off with -o) for useful reports.
// EXPECT-CONTAINS: ----- 480 bytes in 3 allocations -----
// EXPECT-CONTAINS: make_list
// EXPECT-CONTAINS: ----- 5 bytes in 1 allocation -----
// EXPECT-CONTAINS: copy_string
// EXPECT-CONTAINS: Total: 485 bytes in 4 allocations.
// EXPECT-CONTAINS: Marked as non-leaks: 8 bytes in 1 allocation.
#import "Basic"()(MEMORY_DEBUGGER=true);

Settings :: struct { volume: float; fullscreen: bool; }

settings: *Settings;                       // lives for the whole program

make_list :: (n: int) -> [] int {
    result := NewArray(n, int);
    for * result it.* = it_index;
    return result;
}

main :: () {
    settings = New(Settings);
    this_allocation_is_not_a_leak(settings);

    for 1..3 {
        xs := make_list(it * 10);           // 10 + 20 + 30 ints = 480 bytes, never freed
    }
    ok := make_list(5);
    free(ok.data);                          // freed: not reported

    name := copy_string("hello");           // 5 bytes, leaked
    t := tprint("temporary % is never reported", 1);

    report_memory_leaks();
}
