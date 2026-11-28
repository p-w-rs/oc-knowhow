// `for` over your own type: define a macro named for_expansion taking (container, body: Code,
// flags: For_Flags). It must declare `it and `it_index in the caller and #insert the body.
// The user's names (`for v, i: x`) are mapped onto it/it_index automatically. For_Flags carries
// .REVERSE (`for <`) and .POINTER (`for *`); `for <=cond` / `for *=cond` take constant flags.
// Other macros with the same signature are named iterators: `for :name x`.
// `#insert(break = break outer) body` makes the user's `break` leave your OUTER loop.
// EXPECT: oldest->newest: 3 4 5 6
// EXPECT: newest->oldest: 6 5 4 3
// EXPECT: after `for *` x10: [0]=30 [1]=40 [2]=50 [3]=60
// EXPECT: :evens -> 40 60
// EXPECT: grid until 4: 0 1 2 3

#import "Basic";

Ring :: struct (N: int, T: Type) {
    items: [N] T;
    head, count: int;
}

push :: (r: *Ring, v: r.T) {
    r.items[(r.head + r.count) % r.N] = v;
    if r.count < r.N  r.count += 1;
    else              r.head = (r.head + 1) % r.N;
}

for_expansion :: (r: *Ring, body: Code, flags: For_Flags) #expand {
    REVERSE    :: (flags & .REVERSE) != 0;
    BY_POINTER :: (flags & .POINTER) != 0;
    for <=REVERSE i: 0..r.count-1 {
        #if BY_POINTER  `it := *r.items[(r.head + i) % r.N];
        else            `it :=  r.items[(r.head + i) % r.N];
        `it_index := i;
        #insert body;
    }
}

evens :: (r: *Ring, body: Code, flags: For_Flags) #expand {
    n := 0;
    for i: 0..r.count-1 {
        v := r.items[(r.head + i) % r.N];
        if v % 20 != 0 continue;
        `it := v;
        `it_index := n;
        n += 1;
        #insert body;
    }
}

Grid :: struct { w, h: int; }
for_expansion :: (g: Grid, body: Code, flags: For_Flags) #expand {
    for row: 0..g.h-1 {
        for col: 0..g.w-1 {
            `it := col + row * g.w;
            `it_index := row;
            #insert(break = break row) body;     // without this, break would only end the inner loop
        }
    }
}

main :: () {
    r: Ring(4, int);
    for 1..6 push(*r, it);                       // keeps the newest 4: 3 4 5 6
    print("oldest->newest:"); for r   print(" %", it); print("\n");
    print("newest->oldest:"); for < r print(" %", it); print("\n");
    for * r  it.* *= 10;
    print("after `for *` x10:"); for v, i: r print(" [%]=%", i, v); print("\n");
    print(":evens ->"); for :evens r print(" %", it); print("\n");
    print("grid until 4:");
    for Grid.{3, 3} { if it == 4 break; print(" %", it); }
    print("\n");
}
