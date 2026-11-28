// Random: a 128-bit-state MCG whose default state lives in the context
// (context.random_state, added by the module with #add_context), so each thread
// has its own stream. Every procedure also has a variant taking an explicit
// *Random_State. PCG offers the same procedure names with a 32-bit PCG generator
// (its header says it is untested). Import at most one of them unqualified:
// both export random_get(), so the call would match 2 overloads.
// The numbers are the same on arm64 macOS and x64 Linux (checked, 0.2.032).
// EXPECT: Random: 14755925717116703311 10.020587 0.271116
// EXPECT: same seed, same first value: true
// EXPECT: explicit state: 619145600096640801 5368500881011585797
// EXPECT: PCG: 3409023181, die roll (0..5) 0
// EXPECT: 6000 dice: [1012, 969, 1046, 994, 999, 980]

#import "Basic";
#import "Random";
PCG :: #import "PCG";

main :: () {
    random_seed(12345);
    first := random_get();                       // u64
    in_range := random_get_within_range(10, 20); // float
    unit := random_get_zero_to_one();            // float in [0, 1]
    print("Random: % % %\n", first, in_range, unit);
    random_seed(12345);
    print("same seed, same first value: %\n", random_get() == first);

    state: Random_State;                         // a private stream
    random_seed(*state, 99);
    print("explicit state: % %\n", random_get(*state), random_get(*state));

    PCG.random_seed(7);
    print("PCG: %, die roll (0..5) %\n", PCG.random_get(), PCG.random_get_within_bound(6));

    random_seed(2026);
    counts: [6] int;
    for 1..6000  counts[random_get() % 6] += 1;
    print("6000 dice: %\n", counts);
    // Time-based seed: random_seed(cast(S128) current_time_monotonic()).
    // Without the cast it does not compile in 0.2.032: Apollo_Time is a
    // #type,isa S128 and does not match the 128-bit overload directly.
    random_seed(cast(S128) current_time_monotonic());
}
