// Semaphore: init(*s, initial_value), signal(*s), wait_for(*s, milliseconds = -1) -> Wait_For_Result
// (.SUCCESS, .TIMEOUT, .ERROR). Here: a bounded producer/consumer ring buffer with two semaphores
// (free slots, filled slots), plus a timed wait that times out.
// On macOS the Thread module implements Semaphore with Mach semaphores, elsewhere POSIX sem_t.
// Condition_Variable (init/wait(*cv, *mutex)/wake/wake_all) exists too.
// EXPECT: consumer received 50 items, sum of squares 42925
// EXPECT: wait_for with a 10 ms timeout on an empty semaphore: TIMEOUT
#import "Basic";
#import "Thread";

RING :: 8;
ring: [RING] int;
filled: Semaphore;
free_slots: Semaphore;

producer :: (t: *Thread) -> s64 {
    for 1..50 {
        wait_for(*free_slots);                 // block while the ring is full
        ring[it % RING] = it * it;
        signal(*filled);
    }
    return 0;
}

main :: () {
    init(*filled, 0);
    init(*free_slots, RING);
    defer { destroy(*filled); destroy(*free_slots); }

    t: Thread;
    thread_init(*t, producer);
    thread_start(*t);

    received, sum := 0, 0;
    for 1..50 {
        wait_for(*filled);
        sum += ring[it % RING];
        received += 1;
        signal(*free_slots);
    }
    thread_is_done(*t, -1);
    thread_deinit(*t);
    print("consumer received % items, sum of squares %\n", received, sum);

    result := wait_for(*filled, 10);
    print("wait_for with a 10 ms timeout on an empty semaphore: %\n", result);
}
