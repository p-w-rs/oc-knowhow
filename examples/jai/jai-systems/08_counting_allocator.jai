// The Allocator interface is one procedure plus one data pointer:
//     Allocator_Proc :: #type (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void;
// A wrapper that counts and forwards is the smallest useful allocator. Answer .CAPS politely
// (fill the name string when old_memory is non-null) and forward everything else.
// Also shows: a [..] array REMEMBERS the allocator that was current on its first growth,
// and keeps using it later, even outside the scope that pushed it.
// EXPECT: caps name: counting wrapper
// EXPECT: inside the scope: 2 allocations, 1 free
// EXPECT: after growing the array outside the scope: 6 allocations
// EXPECT: array remembered the counting allocator: true
// EXPECT: string and [] views do not carry an allocator: size_of(string)=16, size_of([..] int)=40
#import "Basic";

Counter :: struct {
    allocations: int;
    frees: int;
    backing: Allocator;
}

counting_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    c := cast(*Counter) allocator_data;
    if mode == {
      case .ALLOCATE; #through;
      case .RESIZE;   c.allocations += 1;
      case .FREE;     c.frees += 1;
      case .CAPS;
        // Braces needed: without them, "if old_memory (cast..." parses the parentheses as part of the condition.
        if old_memory { (cast(*string) old_memory).* = "counting wrapper"; }
        return cast(*void) Allocator_Caps.FREE;
    }
    return c.backing.proc(mode, size, old_size, old_memory, c.backing.data);
}

main :: () {
    counter := Counter.{backing = context.allocator};
    counting := Allocator.{counting_allocator_proc, *counter};

    caps, name := get_capabilities(counting);
    print("caps name: %\n", name);

    numbers: [..] int;
    {
        push_allocator(counting);
        array_add(*numbers, 1);            // first growth: allocation 1, array stores 'counting'
        s := sprint("%-%", "temp", 42);    // allocation 2
        free(s);                           // free 1 (free goes through context.allocator too)
    }
    print("inside the scope: % allocations, % free\n", counter.allocations, counter.frees);

    for 2..100 array_add(*numbers, it);    // regrowth goes to numbers.allocator, not context.allocator
    print("after growing the array outside the scope: % allocations\n", counter.allocations);
    print("array remembered the counting allocator: %\n", numbers.allocator.proc == counting_allocator_proc);
    array_free(numbers);                   // frees with numbers.allocator

    print("string and [] views do not carry an allocator: size_of(string)=%, size_of([..] int)=%\n",
        size_of(string), size_of([..] int));
}
