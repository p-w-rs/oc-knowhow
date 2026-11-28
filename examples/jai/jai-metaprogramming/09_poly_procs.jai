// Polymorphic procedures: `$T` DEFINES a compile-time type variable at exactly one place, plain `T`
// uses it. Put the `$` on the argument that should decide the type, so mistakes are reported at
// the other argument. Each distinct T compiles one copy (deduplicated program-wide); a #run inside
// the body runs once per copy. Quick procedures `x => expr` are polymorphic too.
// Headers may end with a trailing comma again (since 0.2.025), handy for long generic signatures.
// EXPECT-COMPILE: [compile time] compiling largest() for T = s64
// EXPECT-COMPILE: [compile time] compiling largest() for T = float32
// EXPECT: largest ints = 9, largest floats = 2.5
// EXPECT: names = ["ada", "bob"] lengths = [3, 3]
// EXPECT: same polymorph for two s64 calls: true
// EXPECT: type of that polymorph: procedure ([] s64) -> s64

#import "Basic";

largest :: (items: [] $T) -> T {
    #run print("[compile time] compiling largest() for T = %\n", T);
    best := items[0];
    for items if it > best best = it;
    return best;
}

// $T on the array: the array decides, a wrong `item` is the reported mistake.
append_item :: (array: *[..] $T, item: T) { array_add(array, item); }

map :: (
    items: [] $T,
    f: (T) -> $R,
) -> [..] R {
    out: [..] R;
    for items array_add(*out, f(it));
    return out;
}

main :: () {
    a := largest(int.[3, 9, 2]);
    b := largest(float.[1, 2.5, -4]);
    c := largest(int.[7, 1]);          // reuses the s64 copy: no second compile-time message
    print("largest ints = %, largest floats = %\n", a, b);

    names: [..] string;
    append_item(*names, "ada");
    append_item(*names, "bob");
    lengths := map(names, s => s.count);
    print("names = % lengths = %\n", names, lengths);

    p1 :: #procedure_of_call largest(int.[1]);
    p2 :: #procedure_of_call largest(int.[5, 6]);
    print("same polymorph for two s64 calls: %\n", p1 == p2);
    print("type of that polymorph: %\n", type_of(p1));
}
