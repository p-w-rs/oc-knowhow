# Cache, layout and allocator benchmarks (Jai beta 0.2.032)

Measurements behind `skill/jai-systems/reference/caches.md`. The example runner skips this folder (its
name starts with `_`): these programs print timings, which differ per machine and run.

| File | Measures |
|---|---|
| `a_locality.jai` | Summing a value through linked lists whose 16-byte nodes come from a Flat_Pool, the default heap (in order, with other sizes in between, with the same size in between, after churn), a fixed-size slot pool after churn, a shuffled array; versus a plain array, an index-linked list, a slot-pool scan and a `Bucket_Array` scan. ns per element, plus where the nodes ended up (share of +16-byte steps, backward steps, line changes per node). |
| `b_aos_soa.jai` | A 64-byte `Particle` as array of structs, struct of arrays and hot/cold split; four loops touching 8, 4, 24 and 32 bytes per element; one extra row that processes four floats per step through a 16-byte struct copy (see "Findings"). |
| `c_false_sharing.jai` | T threads each incrementing their own counter: counters 8 bytes apart, padded to 64, padded to 128, counted locally and stored once; plain stores and `atomic_add`; plus one counter shared by all threads. |
| `d_alignment.jai` | Latency of dependent 8-byte loads at offsets 0, 4, 60, 124, 4092, 16380 inside 16 KiB blocks (aligned, misaligned, crossing a 64/128-byte line, a 4 KiB page, a 16 KiB page); summing and incrementing u64s at offset 0 vs 4 in L1 and in DRAM; arrays of `{u8, u64, u8}` padded (24 B), reordered (16 B) and `#no_padding` (17 B). |
| `e_alloc_speed.jai` | Allocate N blocks then free them (or reset), and steady-state churn, for the default heap, `temp`, `Flat_Pool`, `Pool`, the `rpmalloc` module (release flags) and a fixed-size slot pool (through an `Allocator` and called directly); 32, 256 and mixed 16..512 bytes. With threads: 1 vs 4 threads allocating and freeing 32-byte blocks from the default heap, rpmalloc, or a Flat_Pool per thread. |
| `harness.jai` | Shared by all: `measure` (warm-up run, then median and min of the timed runs), table printing, a Fisher-Yates shuffle. |
| `build.jai` | Builds everything into `bin/` with `set_optimization(.VERY_OPTIMIZED)` and `stack_trace = false`, which is what `jai -o` sets. `e_alloc_speed` gets a 64 MiB first temporary-storage page so `temp` never needs overflow pages. |
| `run.sh` | Builds, stamps the machine (CPU, caches, OS, Jai version, build flags, pinning, load average), runs every benchmark (pinned on Linux) and writes `results/<machine>.md`. |
| `results/` | One file per machine: `mac-m2max.md`, `powerslabs.md`, `ubuntu-laptop.md`. |

## Running

```sh
cd examples/jai/jai-systems/_bench
./run.sh mac-m2max                                   # macOS: no pinning, run on an idle machine
./run.sh powerslabs                                  # Linux: taskset -c 2 (one thread), -c 0-7 (threads)
THREAD_CPUS=0-5 THREADS="2 4 6" ./run.sh ubuntu-laptop   # 6 P-cores on the Core Ultra 7 265H
./run.sh name quick                                  # 3 runs, smaller sizes: checks that everything works
```

Single programs: `jai build.jai` (or `jai build.jai - c_false_sharing`), then `./bin/c_false_sharing 2 4 8`,
`./bin/e_alloc_speed single`, `./bin/e_alloc_speed threads 4`, `./bin/a_locality quick`. On Linux with `perf`
(and `kernel.perf_event_paranoid` ≤ 2, or root): `perf stat -e cache-misses,cache-references,L1-dcache-load-misses
taskset -c 2 ./bin/a_locality` shows the misses behind the timings.

## Method

- Build: the same as `-o` (LLVM O3 with vectorizers, bounds/cast/null checks off, no stack traces).
- Each measurement runs the work once untimed (warm-up: caches, TLB, page faults), then 7 timed runs (3 in quick
  mode); tables show the **median** and, in parentheses, the **minimum**. Times come from `current_time_monotonic`.
- Every kernel's result goes into a checksum that is printed, and every structure is verified (list sums equal
  n(n+1)/2, the three particle layouts end with identical data, every increment is counted, every allocated block
  still holds what was written into it). A kernel whose result is unused would be deleted by the optimizer.
- Kernels take a "salt" that changes every pass and is mixed into the sum, so passes cannot be merged.
- Sizes are chosen to land in L1, L2, the last-level cache and DRAM on all three machines: 32 KiB (L1 everywhere:
  48 KiB on the Intel P-cores, 128 KiB on the M2 Max P-cores), 1 MiB (L2), 8 MiB (L3 on Intel, the 16 MiB shared L2
  on the M2 Max), 32 MiB (around the Intel L3 sizes: 36 and 24 MiB; beyond the M2 Max's L2 but inside its system
  level cache, whose size Apple does not publish) and 128 MiB (DRAM everywhere).
- Threads start together (spin barrier); each thread times its own loop and the slowest one counts.
- Linux runs are pinned to performance cores with `taskset` (single-threaded work on CPU 2; threaded work on the
  P-cores only, so no thread lands on a slower E-core). macOS cannot pin threads: the result files show the load
  average before and after each program.
- Peak resident memory, measured on the Mac with `/usr/bin/time -l`: a_locality 1.07 GB (its largest cases keep
  128 MiB of nodes plus 8.4 million other blocks alive, and macOS malloc keeps the freed memory of earlier cases
  resident), b_aos_soa 0.49 GB, d_alignment and e_alloc_speed 0.2 GB, c_false_sharing 2 MB. A full run took 1–4
  minutes per machine.

## Findings that shaped the code

- **A reverse loop is `for < i: low..high`** (it counts down from high). `for < i: high..low` runs zero times without
  a warning; the first version of the shuffle did nothing and every "shuffled" list was in order.
- **`-o` does not vectorize loops that store through an array view or pointer** in 0.2.032 (on arm64 and x64): the
  IR computes each element address with `ptrtoint`/`inttoptr` and marks every access `align 1`. Read-only integer
  reductions do vectorize. Copying four floats at a time as a 16-byte struct (`F4`) produces vector code (NEON
  `fmul.4s`/`fadd.4s`, SSE `mulps`/`addps`): that is the "4 floats per step" row in `b_aos_soa`.
- A parenthesized expression right after a `for` header (`for i: 1..n (p + i).* += 1;`) does not parse ("Expected a
  statement before this semicolon"): use braces.
- POSIX threads never send `THREAD_START` to `context.allocator`, so a thread that uses the rpmalloc module must call
  `rpmalloc_allocator_proc(.THREAD_START, 0, 0, null, null)` itself (its per-thread heap is an `#add_context` field
  that starts out null).
