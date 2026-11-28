// Atomics: compiler intrinsics (Preload, no import needed) for values up to 8 bytes:
//   compare_and_swap(*x, old, new) -> (success, old_value)   (AcqRel on ARM64 since 0.2.030)
//   atomic_exchange(*x, new) -> old,  atomic_load(*x),  atomic_store(*x, v)   (intrinsics since 0.2.030)
// modules/Atomics adds atomic_add (returns the OLD value), atomic_increment, atomic_decrement
// (returns true when the result is zero), atomic_and/or/xor, and the aliases
// atomic_swap / atomic_read / atomic_write. On x64 they are lock-prefixed #asm; elsewhere CAS loops.
// EXPECT: 8 threads x 100000 atomic_add: 800000
// EXPECT: atomic_add returned the old value: 800000 -> 800005
// EXPECT: compare_and_swap(7 -> 9): success=true old=7 now=9
// EXPECT: compare_and_swap(7 -> 11) on 9: success=false old=9 now=9
// EXPECT: atomic_exchange returned 9, now 1
// EXPECT: atomic_decrement to zero reports true: true
// EXPECT: spin lock protected 80000 increments: 80000
#import "Basic";
#import "Thread";
#import "Atomics";

hits: int;
lock_word: u32;          // 0 = free, 1 = taken
plain: int;

spin_lock :: () {
    while true {
        ok, _ := compare_and_swap(*lock_word, 0, 1);
        if ok return;
    }
}
spin_unlock :: () { atomic_store(*lock_word, 0); }

worker :: (t: *Thread) -> s64 {
    for 1..100_000 atomic_add(*hits, 1);
    for 1..10_000 {
        spin_lock();
        plain += 1;                      // non-atomic, but protected by the spin lock
        spin_unlock();
    }
    return 0;
}

main :: () {
    threads: [8] Thread;
    for * threads { thread_init(it, worker); thread_start(it); }
    for * threads { thread_is_done(it, -1); thread_deinit(it); }
    print("8 threads x 100000 atomic_add: %\n", hits);

    old := atomic_add(*hits, 5);
    print("atomic_add returned the old value: % -> %\n", old, hits);

    v: u32 = 7;
    ok, prev := compare_and_swap(*v, 7, 9);
    print("compare_and_swap(7 -> 9): success=% old=% now=%\n", ok, prev, v);
    ok, prev = compare_and_swap(*v, 7, 11);
    print("compare_and_swap(7 -> 11) on 9: success=% old=% now=%\n", ok, prev, v);
    x := atomic_exchange(*v, 1);
    print("atomic_exchange returned %, now %\n", x, atomic_load(*v));

    refcount: s32 = 1;
    print("atomic_decrement to zero reports true: %\n", atomic_decrement(*refcount));
    print("spin lock protected 80000 increments: %\n", plain);
}
