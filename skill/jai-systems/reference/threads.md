# Threads, synchronization and atomics (deep dive)

Verified on Jai beta 0.2.032 (macOS arm64 M2 Max; Linux x86-64 powerslabs 24 cores and ubuntu-laptop 16 cores).
Examples: `examples/jai/jai-systems/21`, `23`–`27`. Sources: `modules/Thread/module.jai`, `primitives.jai`,
`thread_group.jai`, `modules/Atomics.jai`, `modules/Preload.jai` (atomic intrinsics), `modules/System.jai`
(`get_number_of_processors`), bundle examples `modules/Thread/examples/thread_group.jai` and `mutex_order.jai`.
Real code using threads: `hyperserve-source` (rluba's HTTP server: request threads, a wait group, a main-thread event
loop). Library: `library_search query="thread_init Thread_Group add_work" sources=["jai-modules-src"]`.

## Module parameters

`#import "Thread"(LOAD_THREAD_GROUP = true)(CACHE_LINE_SIZE = 64, DO_RACE_DETECTOR = false, SET_THREAD_NAMES = true);`
- `LOAD_THREAD_GROUP` (module parameter): false skips Thread_Group (the debug allocators import `Thread(false)` to get
  only mutexes).
- `CACHE_LINE_SIZE` pads Thread_Group's per-worker data against false sharing.
- `SET_THREAD_NAMES` (0.2.030): thread names are set on all platforms (on macOS from inside the thread).
- `DO_RACE_DETECTOR=true` does not compile: "Unable to find a module called 'Race_Detector'" (not shipped).
- The mutex lock-order checker (`Mutex_Order`, `DEBUG`) is disabled in the module ("DEBUG is currently disabled");
  `examples/mutex_order.jai` compiles and runs but checks nothing.

## Threads you manage

```jai
Thread_Proc :: #type (*Thread) -> s64;
thread_init   :: (thread: *Thread, proc: Thread_Proc, temporary_storage_size: s32 = 16384,
                  starting_storage: *Temporary_Storage = null, name := "") -> bool;
thread_start  :: (thread: *Thread);
thread_is_done :: (thread: *Thread, milliseconds: s32 = 0) -> bool;   // -1 = wait until it ends
thread_deinit :: (thread: *Thread);
```

- You own the `Thread` struct (global, on the stack while you wait, or in an array); it must stay alive and in place
  until the thread is done and deinitialized. `thread.data` is your `*void` for input/output (example 23 points it at
  a `Job` struct per thread). The proc's return value is the thread's exit code (truncated to s32).
- `thread_init` creates the OS thread **suspended** and prepares its starting context; `thread_start` lets it run.
  `thread_is_done(*t, -1)` waits; `thread_deinit` joins (POSIX) and frees the thread's temporary storage.
- **Hang:** `thread_deinit` on a thread that was initialized but never started blocks forever on macOS and Linux (it
  joins a thread that is still waiting to be started). The same happens to `shutdown` of a `Thread_Group` that was
  `init`ed but never `start`ed. Always start what you initialized (a proc that returns immediately is fine).
- `context.thread_index`: 0 on the main thread; threads get 1, 2, 3, ... from a global atomic counter that is **never
  reused** (three threads created one after another got 1, 2, 3 on Mac and Linux). Per-thread arrays indexed by
  `thread_index` work for a fixed set of long-lived threads; with threads created repeatedly the index keeps growing,
  so bounds-check it (Iprof ignores threads with index ≥ its MAX_THREADS).
- `thread_init_handler: (thread: *Thread)` (global, 0.2.019) runs at the end of every `thread_init` on the creating
  thread: the place to copy `#add_context` fields into `thread.starting_context` (example 24), because a new thread's
  context only inherits `allocator`, `logger`, `logger_data` and `assertion_failed`.
- `get_number_of_processors()` (System; default `.PERFORMANCE_LOGICAL`): measured 8 on the M2 Max (its performance
  cores; the machine has 12), 24 on the 285K, 16 on the 265H. On Linux the performance variants are mapped to all
  logical CPUs (the module says Linux can't tell core types apart).
- Old code: `thread_create` / `thread_destroy` / `thread_uninit` were removed in 0.1.071 (example 11).

## Mutex, Semaphore, Condition_Variable

| Type | Calls | Notes |
|---|---|---|
| `Mutex` | `init(*m, desired_name = "", desired_order = -1)`, `lock(*m)`, `unlock(*m)`, `destroy(*m)` | recursive on POSIX (locking twice on the same thread works, verified); a critical section on Windows; name/order only matter for the disabled DEBUG checks |
| `Semaphore` | `init(*s, initial = 0)`, `signal(*s)`, `wait_for(*s, milliseconds = -1) -> Wait_For_Result`, `destroy(*s)` | `.SUCCESS`, `.TIMEOUT`, `.ERROR`; macOS uses Mach semaphores (no `sem_timedwait` there), Linux `sem_t` |
| `Condition_Variable` | `init(*cv)`, `wait(*cv, *mutex)`, `wake(*cv)`, `wake_all(*cv)`, `destroy(*cv)` | `wait` releases the mutex while sleeping; loop on your predicate (verified producer/consumer round trip) |

- `wait_for(*s, 10)` on an empty semaphore returned `.TIMEOUT` after 10 ms (example 27). Example 27 builds a bounded
  ring buffer with two semaphores (free slots, filled slots): 50 items through 8 slots, sum of squares 42925.
- There is no RAII lock guard; use `lock(*m); defer unlock(*m);`.

## Thread_Group (worker pool)

```jai
Thread_Group_Proc :: #type (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status;
init :: (group: *Thread_Group, num_threads: s32, group_proc: Thread_Group_Proc, enable_work_stealing := false,
         temporary_storage_size: s32 = 16384, group_name := "");
start, add_work(group, work: *void, logging_name := ""), get_completed_work(group) -> [] *void, shutdown(group, timeout_ms = -1) -> bool
```

- Design (described in the module): every worker runs the same procedure; each worker has its own input and output
  queue to avoid all cores fighting over one queue's cache lines; work is handed out round-robin; with
  `enable_work_stealing = true` an idle worker takes work from others. The group remembers its allocator for its
  bookkeeping (only the calling thread allocates; workers don't).
- `group.logging` is **true by default** and logs every step, e.g.
  `'workers' added     work 'first item' to the available list at time 0.` and
  `'workers' completed work 'first item' from thread 1 at time 0.001019 (elapsed: 0.001019).` Set it false after
  `init`. `group.time_proc` overrides the clock used in these logs; `group.data` is free for you.
- `get_completed_work` returns the work pointers that finished since the last call, in **temporary storage** of the
  calling thread: reset temp regularly in the polling loop (example 25 polls, sums, resets, sleeps 1 ms).
- Return `.STOP` from the proc to end that worker (for unrecoverable problems); normally `.CONTINUE`.
- `shutdown` signals all workers, waits (or up to `timeout_milliseconds`; returns false if they did not finish, and
  then nothing was freed: call it again) and frees them. Work items are your memory: keep them alive until they come
  back.
- Each worker has its own temporary storage (`temporary_storage_size` per worker): call `reset_temporary_storage()` at
  the end of each work item, as example 25 does.
- Example 25: 64 chunks of a 64000-number sum on (processors − 1, max 8) workers with work stealing; total 2048032000
  equals the formula, every chunk ran on a worker (thread_index ≠ 0).

## Atomics

- Intrinsics in Preload (no import; values up to 8 bytes): `compare_and_swap(*x, old, new) -> (success: bool,
  old_value)` (since 0.2.003; replaces `lock_cmpxchg`, removed 0.2.009; AcquireRelease on ARM64 since 0.2.030),
  `atomic_exchange(*x, new) -> old`, `atomic_load(*x)`, `atomic_store(*x, v)` (0.2.030, for ARM64).
- `#import "Atomics"`: `atomic_add(*x, delta) -> old value` (since 0.1.027 it returns the old value), `atomic_increment`,
  `atomic_decrement -> bool` (true when the result is zero: reference counts), `atomic_and`, `atomic_or`, `atomic_xor`,
  aliases `atomic_swap = atomic_exchange`, `atomic_read = atomic_load`, `atomic_write = atomic_store`, and the x64-only
  `atomic_bit_test_and_set`. On x64 these are `lock`-prefixed `#asm`; elsewhere compare-and-swap loops.
- Example 26: 8 threads × 100000 `atomic_add` = 800000; a spin lock from `compare_and_swap` + `atomic_store` protected
  80000 plain increments. Spin locks are for very short critical sections; a `Mutex` sleeps instead.
- Runtime_Support's `one_time_init(*state, code)` (macro) runs code exactly once across threads with a CAS-based state
  machine; Basic uses it for `seconds_since_init`.

## What is (not) thread-safe

| Thing | Thread-safe? |
|---|---|
| Default allocator (rpmalloc-based on x64, C malloc on arm64), rpmalloc module | yes (`MULTIPLE_THREADS` in CAPS) |
| `temp` / temporary storage | per thread: safe because nothing is shared; never pass temp memory to a thread that may use it after your reset |
| Flat_Pool, Pool, your arenas | no: one per thread, or wrap with a Mutex |
| `print`, `write_string`, `log` with the default logger | each `write_string` is serialized by a lock in Runtime_Support; `print` formats into a String_Builder first and then writes it, so lines from threads did not interleave in our tests (example 23 locks a mutex around print anyway) |
| Hash_Table, `[..]`, String_Builder | no locking: one owner, or guard with a Mutex |
| Memory debugger | yes (mutex), records the thread index of allocations and frees |
| Iprof | per-thread zones since 0.2.031 (`thread_index < MAX_THREADS`) |

Contexts are per thread, so `#add_context` fields are thread-local state, but remember they start at their
initializers in new threads unless `thread_init_handler` copies them.

## Related modules

- `Shared_Memory_Channel`: one-reader/one-writer message channel between processes (`reader_create_channel`,
  `writer_connect`, `writer_reserve_message`, `writer_commit_message`, `reader_poll_for_message`,
  `reader_done_with_message`); the memory visualizer uses it. Bundle example: start `read`, then `write`.
- `File_Watcher`: directory watcher (`init(*watcher, callback, ...)`, `add_directories`, `process_changes`); its
  example runs forever.
- `Process`: run child processes (`run_command`, parallel runs).
