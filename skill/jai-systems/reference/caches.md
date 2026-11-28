# Caches, layout and allocators, measured (deep dive)

Measured with Jai beta 0.2.032 on mac-m2max, powerslabs and ubuntu-laptop, 27 Nov 2026. Every number below comes
from the result files of the benchmark suite in `examples/jai/jai-systems/_bench/` (sources, `build.jai`, `run.sh`,
README with the method), cited as **[M]** = `results/mac-m2max.md`, **[P]** = `results/powerslabs.md`,
**[L]** = `results/ubuntu-laptop.md`. Facts printed by the runner examples: 46 (where list nodes land), 47 (bytes per
element in AoS/SoA), 48 (which line each counter is on), 49 (alignment). Build for all timings: `-o` settings
(VERY_OPTIMIZED, checks off, no stack traces); median of 7 runs after a warm-up run.

| Name in files | Machine | Notes for reading the numbers |
|---|---|---|
| mac-m2max | Apple M2 Max, macOS 26.6, LLVM backend | no pinning possible; load average 3.4–5.7 during the run (other processes) |
| powerslabs | Intel Core Ultra 9 285K, Linux 7.2 | pinned to P-cores (`taskset -c 2`, threads `-c 0-7`); idle (load 0.1) |
| ubuntu-laptop | Intel Core Ultra 7 265H, Ubuntu 26.10 | pinned (`-c 2`, threads `-c 0-5`); "balanced" power profile: its L1 load latency was 1.75 ns vs 0.73 ns on powerslabs, so compare ratios within the machine, not absolute times |

## Cache basics that matter for Jai code

- Memory moves between DRAM and the core in **cache lines**: 64 bytes on both Intel machines, **128 bytes on the
  M2 Max**. Reading one byte loads its whole line; writing one byte needs the whole line in this core's cache.
  Everything below (padding, AoS vs SoA, node sizes) is about how many lines a loop touches.
- Each level is bigger and slower. Reported sizes (Mac: `sysctl hw.*`; Linux: `/sys/devices/system/cpu/cpuN/cache`):

| | mac-m2max | powerslabs (285K) | ubuntu-laptop (265H) |
|---|---|---|---|
| line | 128 B | 64 B | 64 B |
| L1 data | P-core 128 KiB, E-core 64 KiB | P-core 48 KiB, E-core 32 KiB | P-core 48 KiB, E-core 32 KiB |
| L2 | 16 MiB per cluster of 4 P-cores; E: 4 MiB | 3 MiB per P-core; E: 4 MiB per 4 cores | 3 MiB per P-core; E: 4 MiB per 4; LP-E: 2 MiB per 2 |
| L3 | none reported by `sysctl` (Apple's system level cache size is not published) | 36 MiB shared | 24 MiB shared (not by the 2 LP-E cores) |
| page | 16 KiB | 4 KiB | 4 KiB |
| measured: dependent load in L1 (d_alignment) | 0.95 ns | 0.73 ns | 1.75 ns |
| measured: dependent load, random in 128 MiB (a_locality, shuffled list) | 105 ns | 102 ns | 462 ns |

- The benchmark sizes were picked from this table: 32 KiB fits every L1, 1 MiB every L2, 8 MiB the Intel L3s and the
  M2's L2, 32 MiB is near/over the Intel L3s, 128 MiB is DRAM everywhere.
- **Hardware prefetchers** watch the addresses a core loads and fetch lines before they are asked for: the next line,
  constant strides, streams within a page; Intel documents an L2 "spatial prefetcher" that fetches the other 64-byte
  half of each 128-byte pair (the false-sharing test below found no cost from it). They see addresses, not pointers:
  an array or a list whose nodes happen to be in memory order streams; a list in random order gets no help. The M2
  Max went further: the Flat_Pool list (every next node 16 bytes further) walked at 0.33 ns per node in L1, a third
  of one dependent L1 load (0.95 ns, d_alignment), so the core must have loaded nodes before their addresses
  arrived; the heap list, same layout but with a few gaps where the allocator moved to a new run of blocks, took
  0.95 ns [M]. Apple does not document this; don't count on it, but don't be fooled by it in benchmarks either.
- The **TLB** caches page translations. Walking 128 MiB of scattered nodes (churned or shuffled) missed the data TLB
  0.76–1.15 times per node on ubuntu-laptop and missed the last-level cache 2.3–2.5 times per node (perf, [L]
  addendum); the same nodes laid out contiguously: 0.0006 TLB misses and 0.33 LLC misses per node. Bigger pages help
  random access: macOS uses 16 KiB, Linux 4 KiB (transparent huge pages are `madvise`-only on both Linux machines,
  and neither Flat_Pool nor the default heap asks for them; the rpmalloc module has a `LINUX_HUGE_PAGES` parameter,
  not measured here).
- Reading the line size inside a Jai program (example 48): macOS `sysctlbyname("hw.cachelinesize", ...)` from
  `#import "POSIX"` returned 128; Linux `sysconf(._SC_LEVEL1_DCACHE_LINESIZE)` returned 64; page size `getpagesize()`.

## Coherence: two meanings, both measured

"Cache coherence" is used for two different things; both matter for speed.

1. **The hardware protocol** (MESI-style): every cache line has an owner state per core. A core may read a line
   other cores also hold (shared), but to **write** it must hold it **exclusively**: the other copies are invalidated
   first, and the next reader on another core has to fetch it back. Two cores writing the same line take turns owning
   it; every handover costs a cross-core transfer. The protocol keeps every copy of a line consistent, so false
   sharing never corrupts data (ordering between different variables is a separate matter: atomics and locks); it
   costs time. Two ways to hit it:
   - **False sharing**: threads write *different* variables that happen to sit in the *same line*.
   - **True sharing / contention**: threads write the *same* variable (a shared counter, a lock, a queue head).
2. **Informally, "cache-friendliness"**: how well data layout and access order use lines, prefetchers and the TLB
   (contiguous arrays, few pointer chases, small hot data). That is a single-core property: see "Lists, arrays and
   allocators (locality)" and "AoS, SoA and hot/cold splitting" below.

### False sharing and contention (c_false_sharing)

T threads each add 1 to their own counter 20 million times; ns per increment of the slowest thread; "×" = slowdown
against counters in their own 128-byte slot. Plain = load/add/store (fine without atomics: no other thread writes
that counter); atomic = `atomic_add`. Counter block 128-byte aligned (checked at run time). All counts verified.

| layout | mac-m2max 2 / 4 threads [M] | powerslabs 2 / 4 / 8 [P] | ubuntu-laptop 2 / 4 / 6 [L] |
|---|---|---|---|
| plain, own 128-byte slot | 2.10 / 2.20 ns | 1.16 / 1.18 / 1.19 ns | 3.51 / 3.10 / 2.78 ns |
| plain, padded to 64 | 1.0× / 1.0× | 1.0× / 1.0× / 1.0× | 0.9× / 1.0× / 1.0× |
| plain, adjacent (8 bytes apart) | 1.0× / 1.1× | 1.3× / 2.2× / 2.7× | 1.1× / 1.8× / 2.5× |
| plain, count in a local, store once | 0.1× | 0.1× | 0.1× |
| atomic, own 128-byte slot | 4.76 / 4.93 ns | 3.65 / 3.72 / 3.72 ns | 9.37 / 9.36 / 8.78 ns |
| atomic, padded to 64 | **1.7× / 1.7×** | 1.0× / 1.0× / 1.0× | 1.0× / 1.0× / 1.0× |
| atomic, adjacent | 3.7× / 15.7× | 5.6× / 10.3× / 20.2× | 3.9× / 9.6× / 15.7× |
| atomic, one shared counter (true sharing) | 3.7× / 16.2× | 5.1× / 10.3× / 20.2× | 5.1× / 9.4× / 15.6× |

What it says:
- **Is 64-byte padding enough?** On the M2 Max, **no**: two counters 64 bytes apart share a 128-byte line, and
  atomics on them ran 1.7× slower than on separate lines. On both Intel chips, **yes**: 64-byte padding measured
  1.0× at every thread count, plain and atomic; the adjacent-line prefetcher pairing 64-byte lines caused no
  measurable false sharing here. **Pad per-thread hot data to 128 bytes**: required on Apple silicon, harmless on
  Intel (it costs memory only: 8 counters = 1 KiB).
- Contention grows with the thread count: one shared atomic counter costs 9–20× per increment with 4–8 threads, and
  adjacent per-thread counters are just as bad: false sharing is contention you didn't ask for.
- Counting in a local and publishing once beats any layout by ~10× even single-threaded (the in-memory increment is a
  load-store dependency every iteration). **Shard and combine**: per-thread partial results, summed at the end; batch
  updates to shared state (add 1000 at once, not 1 a thousand times).
- On the M2 Max, plain stores to adjacent counters were nearly free (1.0–1.1×) while atomics were not. A likely
  reason (not verified): Arm's weaker memory ordering lets a core merge many stores to a line before it must own the
  line, and each increment reads its own previous store from the store buffer; x86 must make stores visible in order.
  Don't rely on it: any read-modify-write that must see the other core's value (atomics, locks) pays.
- x64 `atomic_add` is `lock xadd`; on arm64 0.2.032 compiles it to a load-exclusive/store-exclusive retry loop (no LSE
  instructions in the disassembly), and `atomic_store` to `stlr`.

### Padding in Jai

- `value: s64 #align 128;` as a member makes the struct 128 bytes and 128-aligned; `#align` also works on globals and
  locals (verified on all three machines: globals up to `#align 4096`, locals up to 128). Example 48 prints which
  line each counter lands on.
- **The heap ignores `#align`**: `New(T)` asks its allocator for `size_of(T)` bytes, and `Allocator_Proc` has no
  alignment parameter. The default heap returned 16-byte-aligned blocks everywhere; on macOS, `NewArray(8,
  Padded_128)` started 48 or 80 bytes past a 128-byte boundary (on powerslabs it happened to land aligned). Use
  `slots, base := NewArray(n, T, alignment = 128);` and later `free(base)` (not `slots.data`).
- `Thread_Group` pads each worker's record with the Thread module's `CACHE_LINE_SIZE` (default 64; `NewArray(...,
  alignment=CACHE_LINE_SIZE)` and an assert on the array start). On Apple silicon set it: `#import
  "Thread"()(CACHE_LINE_SIZE=128);` — it is in the **second** (program) parameter list; `#import
  "Thread"(CACHE_LINE_SIZE=128);` fails with "Argument name 'CACHE_LINE_SIZE' (number 1) is not found in the module
  parameters." Read it back through a named import (`Thread_Module :: #import "Thread";` then
  `Thread_Module.CACHE_LINE_SIZE`). Verified effect: `Worker_Info` grows from 4816 to 4880 bytes; its size is a
  multiple of the line size plus 16 (a `[] s32` follows the padding), so only element 0 starts on a line boundary.

## Lists, arrays and allocators (locality)

a_locality sums one value per element. All lists have 16-byte nodes (`next`, `value`) and are walked in list order;
only where the allocator put the nodes differs. ns per element at **32 KiB / 1 MiB / 8 MiB / 128 MiB** of nodes
(n = 2048 / 65536 / 524288 / 8388608):

| structure | mac-m2max [M] | powerslabs [P] | ubuntu-laptop [L] |
|---|---|---|---|
| array of s64 (8 B, vectorized sum) | 0.16 / 0.16 / 0.16 / 0.16 | 0.05 / 0.09 / 0.14 / 0.27 | 0.15 / 0.21 / 0.30 / 0.64 |
| index list in one array (8 B nodes) | 0.40 / 0.35 / 0.38 / 0.56 | 0.91 / 0.91 / 0.91 / 1.58 | 1.01 / 2.18 / 2.19 / 3.65 |
| list, nodes from a Flat_Pool | 0.33 / 0.86 / 0.34 / 0.53 | 0.73 / 0.73 / 0.74 / 2.35 | 0.81 / 1.75 / 1.77 / 5.07 |
| list, default heap, allocated in a row | 0.95 / 0.88 / 0.56 / 0.76 | 0.73 / 0.77 / 0.76 / 2.36 | 0.81 / 1.84 / 1.80 / 5.07 |
| list, heap, 8..64-byte blocks allocated between nodes | 0.95 / 0.98 / 1.03 / 1.19 | 0.73 / 0.86 / 0.86 / 1.84 | 0.81 / 2.06 / 2.05 / 4.16 |
| list, heap, 16-byte blocks allocated between nodes | 0.88 / 1.10 / 0.88 / 1.08 | 0.88 / 0.83 / 0.87 / 1.32 | 2.11 / 2.00 / 2.26 / 2.74 |
| list, heap after churn | 0.95 / 3.60 / 4.32 / **48.4** | 0.96 / 2.86 / 7.57 / **50.6** | 2.30 / 6.85 / 16.0 / **224** |
| list, slot pool after churn | 0.94 / 3.56 / 4.23 / **32.6** | 0.73 / 2.83 / 7.55 / **50.6** | 1.75 / 6.78 / 15.9 / **223** |
| slot pool scanned in memory order | 0.51 / 0.53 / 0.53 / 0.55 | 0.23 / 0.29 / 0.36 / 0.72 | 0.54 / 0.59 / 0.82 / 1.66 |
| Bucket_Array(Node, 1024) scan | 0.49 / 0.50 / 0.53 / 0.54 | 0.25 / 0.30 / 0.39 / 1.26 | 0.59 / 0.62 / 0.89 / 2.88 |
| list in random order (shuffled) | 0.94 / 5.74 / 7.91 / **105** | 0.73 / 4.15 / 13.6 / **102** | 1.75 / 8.80 / 27.9 / **462** |

Churn = build the list, free a random half of its nodes in random order, allocate replacements for those positions.
Where the nodes ended up (same on all three machines at 8 MiB and up; share of steps to the next 16 bytes / share of
steps backwards / 64-byte lines entered per node):

| list | layout | what happened |
|---|---|---|
| Flat_Pool, heap in a row | 1.00 / 0.00 / 0.25 | contiguous: four nodes per 64-byte line |
| heap + other sizes between | 0.84 / 0.00 / 0.29 | other sizes go to other size classes: still nearly contiguous |
| heap + same size between | 0.00 / 0.00 / 0.50 | every other block is a stranger: half the density |
| heap or slot pool after churn | 0.25 / 0.38 / 0.81 | freed blocks are reused newest-first: scattered, often backwards |
| shuffled | 0.00 / 0.50 / 1.00 | a new line at every node |

Hardware counters for four of the 128 MiB cases are in [L] (addendum): per node, the Flat_Pool list missed L1 0.011
times and the last-level cache 0.33 times; the churned list 2.0 and 2.3 times plus 0.76 TLB misses.

What it means for choosing allocators and data structures:
- **Order matters more than the allocator.** A bump arena (Flat_Pool, Pool, `temp`) places nodes in allocation
  order, one after another; the default heap did too when the nodes were allocated in a row (x64: rpmalloc-style
  size-class spans; macOS malloc: same result), and other sizes in between hardly mattered. Even contiguous, a list
  walk cost 8–9× the array sum at 128 MiB on Intel (2.35 vs 0.27 ns [P], 5.07 vs 0.64 [L]) and 3.3× on the M2
  (0.53 vs 0.16 [M]): one dependent load per node and twice the bytes. Scanning the same kind of nodes in memory
  order without following links was 3× faster than the walk on powerslabs (slot pool scan 0.72 ns).
- **Churn destroys order, whatever the allocator.** A free list hands out the most recently freed block first, so after
  churn a list visits memory in a scattered, partly backwards order. At 128 MiB that walk cost 20–90× the contiguous
  one (48.4 vs 0.53 ns [M], 50.6 vs 2.35 [P], 224 vs 5.07 [L]) and approached a fully random walk. A fixed-size slot
  pool is fast to allocate from (see "Allocator speed") but gives **no** locality guarantee after reuse: on Intel the
  churned slot pool and the churned heap measured the same.
- **Iterate storage, not links, when order does not matter**: the same churned pool scanned slot by slot (skipping
  free slots) ran 60–135× faster than its list walk at 128 MiB (0.55 vs 32.6 [M], 0.72 vs 50.6 [P], 1.66 vs 223 [L]).
  Pools with an occupancy flag or a dense array plus handles give you both.
- **Rebuild after churn** if a walk order matters: copy the live nodes in walk order into a fresh arena and reset the
  old one (one pass, then contiguous again).
- **Index lists** (`next: s32` into one array) halve the node (8 bytes here), survive a reallocation or a save to disk,
  and walked at 0.56 / 1.58 / 3.65 ns at 128 MiB: faster than the 16-byte pointer list on Intel.
- **Bucket_Array** keeps stable addresses and scans its buckets in order: 0.54 / 1.26 / 2.88 ns per element at 128 MiB,
  within 2× of the slot-pool scan. Each bucket stores an `occupied` bool array followed by the items.
- **Same-size neighbours** (two kinds of 16-byte object allocated alternately) halve the density of each kind's
  lines. Give hot, walked objects their own arena or pool.
- Two oddities you should not build on: on the M2 Max the Flat_Pool list was 2.5× slower at 1 MiB than at 8 MiB
  (0.86 vs 0.34 ns), and on the Intel machines the sparser lists (strangers between nodes) walked faster than the
  contiguous ones out of the L3 (128 MiB: 1.32 vs 2.35 ns [P], 2.74 vs 5.07 [L]; ubuntu-laptop also at 32 MiB). We
  did not find the cause (prefetcher behaviour is undocumented).

## AoS, SoA and hot/cold splitting

b_aos_soa: a 64-byte `Particle` (x, y, z, vx, vy, vz, mass, age, color, id, seed, name) as an array of structs (AoS),
as one array per field (SoA), and as `[] Hot` (x..vz, 24 bytes) + `[] Cold` (the rest). ns per element at
**32 KiB / 8 MiB / 128 MiB** of AoS data; all layouts end with identical results.

| loop (bytes used per element) | layout | mac-m2max [M] | powerslabs [P] | ubuntu-laptop [L] |
|---|---|---|---|---|
| `x += vx*dt` (8 of 64) | AoS | 0.33 / 0.91 / 1.25 | 0.20 / 1.38 / 2.88 | 0.61 / 3.31 / 4.60 |
| | SoA | 0.35 / 0.32 / 0.47 | 0.17 / 0.22 / 0.25 | 0.52 / 0.52 / 0.62 |
| | hot/cold | 0.34 / 0.46 / 0.50 | 0.20 / 0.37 / 1.23 | 0.48 / 0.87 / 2.08 |
| | SoA, 4 floats per step | 0.09 / 0.11 / 0.15 | 0.06 / 0.09 / 0.16 | 0.13 / 0.21 / 0.53 |
| sum of `id` (4, a cold field) | AoS | 0.27 / 0.65 / 1.09 | 0.20 / 1.20 / 3.03 | 0.48 / 2.80 / 6.03 |
| | SoA | 0.12 / 0.12 / 0.12 | 0.08 / 0.08 / 0.11 | 0.19 / 0.19 / 0.44 |
| | hot/cold | 0.28 / 0.40 / 0.69 | 0.20 / 0.69 / 1.72 | 0.49 / 1.64 / 3.65 |
| `pos += vel*dt` (24: exactly Hot) | AoS | 0.52 / 1.11 / 1.27 | 0.28 / 1.36 / 3.25 | 0.68 / 3.20 / 6.75 |
| | SoA | 0.76 / 0.95 / 1.39 | 0.55 / 0.72 / 1.20 | 1.31 / 1.92 / 2.29 |
| | hot/cold | 0.53 / 0.69 / 0.72 | 0.28 / 0.58 / 1.62 | 0.68 / 1.39 / 2.84 |
| all 8 floats → `out[]` (32) | AoS | 0.80 / 0.83 / 1.20 | 0.74 / 1.34 / 2.69 | 1.80 / 3.13 / 6.30 |
| | SoA | 0.93 / 1.38 / 2.52 | 0.74 / 0.74 / 1.04 | 1.79 / 1.77 / 2.14 |
| | hot/cold | 0.79 / 0.84 / 1.11 | 0.74 / 1.20 / 2.39 | 1.78 / 3.01 / 5.18 |

What it says:
- Once data leaves L1, a loop pays for every line it touches. Reading 4 bytes of each 64-byte struct: SoA was 9× (Mac),
  28× (powerslabs) and 14× (laptop) faster than AoS at 128 MiB. Updating 8 of 64 bytes: 2.7×, 11.5×, 7.4×. In L1 the
  layouts stayed within 2.5× of each other.
- **Hot/cold split** gets most of that for loops over the hot fields with one extra array to manage: for the 24-byte
  update it was the fastest layout from 1 MiB up on the Mac and from 1 to 32 MiB on the Intel machines (SoA won at
  128 MiB there), and tied AoS in L1 (results files have the 1 MiB and 32 MiB columns).
- **SoA is not free**: each field is a separate stream. When a loop needs many fields, SoA can lose: all 8 floats on
  the Mac at 128 MiB took 2.52 ns with SoA vs 1.20 with AoS; `pos += vel` in L1 was slower in SoA on all three (6
  streams). Choose the layout per hot loop: split by which fields are used together.
- **`-o` did not vectorize any loop that stores through an array view or pointer** in 0.2.032 (arm64 and x64; the IR
  computes each element address with integer casts and marks every access `align 1`, so LLVM cannot prove the stores
  don't overlap the loads). Read-only integer reductions do vectorize (SSE2 on x64 by default). Processing four
  floats per step through a 16-byte struct copy (`F4 :: struct { a, b, c, d: float32; }`, cast the data pointer,
  load `p := xs[i]`, compute per member, store `xs[i] = p`) produced NEON `fmul.4s`/`fadd.4s` and SSE `mulps`/`addps`:
  1.2–5.4× faster than the scalar SoA loop (the gain shrinks in DRAM, where bandwidth limits). Check the disassembly
  before believing a loop is vectorized.

Doing SoA in Jai:
- By hand (example 47): a struct with one `[] T` per field, all with the same count; allocate each with
  `NewArray(n, T, alignment = 64)` (or one block carved into ranges); loop with `for i: 0..count-1` over the arrays you
  need. To act on several fields of one type, a typed literal of pointers works: `for (*[] float32).[*s.x, *s.y]`
  (an untyped `[*s.x, *s.y]` does not compile as a `for` range).
- Hot/cold: two arrays indexed alike (`hot[i]`, `cold[i]`); keep them the same length on add and remove.
- Generated: Jai's metaprogramming can write the SoA struct from `type_info(T).members` with `#insert` (see the
  **jai-metaprogramming** skill). `modules/Soa.jai` does this for fixed-size arrays (`Soa(T, N)` plus a `for`
  expansion) but its own header calls it unfinished experimentation: read it as an example, don't depend on it.

## Alignment and packing

- **Natural alignment**: a value of size 1, 2, 4 or 8 bytes is stored at an address divisible by its size. A struct's
  alignment is its largest member's, and its size is rounded up to a multiple of it (so arrays stay aligned). Jai
  keeps declaration order and inserts padding where needed: `{u8, u64, u8}` is 24 bytes, `{u64, u8, u8}` 16
  (examples 30, 49). Order members from large to small. Measured sizes/alignments (example 49): `string` and `[] T`
  16/8, `[..] T` 40/8, `Any` 16/8, `[3] u16` 6/2.
- **Why compilers pad**: an aligned value never straddles a cache line or a page, so one access touches one line;
  atomic instructions require it.
- **Jai has no `align_of`**. `type_info(T).alignment` (added 0.2.030) reads **-1** in 0.2.032 for any struct that
  appears in the type of a procedure parameter or return value or of a global (compile time and run time, Mac and
  Linux; the layout itself is correct; example 49). Reliable: `Align_Probe :: struct (T: Type) { first: u8; value: T; }`
  and `type_info(Align_Probe(T)).members[1].offset_in_bytes`.
- Rounding up: `align_forward(value, alignment)` in Basic (any positive alignment); for powers of two
  `(x + a - 1) & ~(a - 1)` gives the same.
- Where alignment comes from: `#align N` on members, globals, locals; the default heap gives 16 bytes; `temp` gives 8
  (`talloc(3)` then `talloc(8)` are 8 bytes apart); Flat_Pool and Pool use their `alignment` field (default 8;
  verified for Flat_Pool in example 49, Pool has the same field in its source; set
  `pool.alignment = 64` before the first allocation); `NewArray(..., alignment = N)` for anything more.
- **`#no_padding` is not a packed layout**: members keep their aligned offsets and only the trailing padding goes
  (size 17 for `{u8, u64, u8}`, so in an array element 1's `u64` sits at byte 25). See example 30.

When misalignment costs (d_alignment):

| access | mac-m2max [M] | powerslabs [P] | ubuntu-laptop [L] |
|---|---|---|---|
| dependent 8-byte load, aligned | 0.95 ns | 0.73 ns | 1.75 ns |
| misaligned within a line (offset 4) | 1.25 | 0.73 | 1.75 |
| crossing a 64-byte line (offset 60) | 1.26 | **2.00** | **4.80** |
| crossing a 64- and a 128-byte line (124) | 1.26 | 2.00 | 4.70 |
| crossing a 4 KiB page (4092) | 1.25 | 2.00 | 4.44 |
| crossing a 16 KiB page (16380) | **9.76** | 2.00 | 4.31 |
| sum of u64s, 128 MiB, offset 0 vs 4 | 0.23 vs 0.23 | 0.35 vs 0.34 | 0.88 (min 0.71) vs 0.73 |
| `+= 1` on u64s, 128 MiB, offset 0 vs 4 | 0.46 vs 0.47 | 0.48 vs 0.49 | 1.02 vs 1.03 |
| sum of `b` over 4M `{u8, u64, u8}`: padded 24 B / reordered 16 B / `#no_padding` 17 B | 0.43 / 0.29 / 0.30 | 0.92 / 0.97 (min 0.63) / 0.74 | 2.14 / 1.44 / 1.60 |

- Latency-bound code (pointer chasing, dependent loads) pays for a load that crosses a line: 2.5–2.7× on Intel. The M2
  charges about 0.3 ns for any misaligned load and ~10× for one that crosses a 16 KiB page (macOS's page size).
- Throughput-bound loops hid it completely: streaming sums and increments at offset 4 matched aligned ones.
- Arrays of the 17-byte `#no_padding` struct read **faster** than the padded 24-byte ones out of cache (fewer bytes)
  and matched them in L1. Smaller is what pays; reordering the members (16 bytes, aligned) was as fast or faster on
  the Mac and ubuntu-laptop without any misalignment (powerslabs' reordered run was noisy: median 0.97, min 0.63).
  `#no_padding` still breaks atomics and C layouts and is not a wire format.
- **Never put atomics on misaligned addresses**: on x86 a locked access across two lines is a *split lock* (it locks
  the memory bus; both Intel machines report `split_lock_detect` and run with `split_lock_mitigate = 1`, which per the
  kernel documentation warns and slows the offending task); on arm64 a load/store-exclusive (what Jai's atomics
  compile to) on a misaligned address is an alignment fault per the Arm architecture. Not benchmarked on purpose.

## Allocator speed

e_alloc_speed, one thread: ns per allocation and per free; "batch" = allocate 100,000 blocks (each gets one 8-byte
store), then free them in order or reset; "churn" = 10,000 live blocks, 1,000,000 steps of free-a-random-one +
allocate. All calls through Basic's `alloc`/`free` with the allocator pushed once, except "slot pool, direct". The
rpmalloc module was imported with `ENABLE_STATISTICS`, `ENABLE_ASSERTS` and `ENABLE_VALIDATE_ARGS` false (its own advice
for release builds). Default heap = C malloc on the Mac, the stripped-down rpmalloc of `modules/Default_Allocator` on
x64. A reset of 100,000 bump allocations took 0–150 ns [M][P] and 63–221 ns [L] in total: free, in practice
(several resets read 0 ns, below the clock's resolution).

32-byte blocks: allocate / free / churn step

| allocator | mac-m2max [M] | powerslabs [P] | ubuntu-laptop [L] |
|---|---|---|---|
| default heap | 12.7 / 13.0 / 39.9 | 19.4 / 9.41 / 15.6 | 30.6 / 20.3 / 37.8 |
| `temp` + reset | 3.08 / reset | 2.78 / reset | 6.72 / reset |
| Flat_Pool + reset | 4.69 / reset | 4.12 / reset | 10.1 / reset |
| Pool + reset | 5.13 / reset | 5.67 / reset | 13.6 / reset |
| rpmalloc (release flags) | 4.26 / 4.34 / 13.9 | 3.27 / 2.39 / 9.94 | 7.79 / 5.72 / 24.2 |
| fixed-size slot pool via an Allocator | 2.26 / 1.27 / 3.43 | 1.53 / 1.75 / 2.65 | 4.75 / 4.19 / 7.29 |
| slot pool, direct calls | 1.09 / 0.71 / 2.26 | 0.94 / 1.21 / 1.33 | 2.25 / 2.86 / 3.12 |

256-byte blocks and mixed 16..512-byte blocks: allocate / free / churn step

| allocator | mac-m2max 256 B · mixed [M] | powerslabs 256 B · mixed [P] | ubuntu-laptop 256 B · mixed [L] |
|---|---|---|---|
| default heap | 13.5 / 11.1 / 44.4 · 24.2 / 21.6 / 56.6 | **71.9** / 30.2 / 22.7 · **65.5** / 34.1 / 15.8 | **122** / 45.4 / 54.7 · **130** / 48.9 / 38.1 |
| `temp` + reset | 3.92 · 5.05 | 4.53 · 6.05 | 11.7 · 17.3 |
| Flat_Pool + reset | 5.87 · 5.77 | 6.05 · 7.43 | 15.3 · 17.5 |
| Pool + reset | 5.94 · 7.75 | 7.47 · 9.21 | 19.4 · 21.6 |
| rpmalloc (release flags) | 6.13 / 4.31 / 19.8 · 7.12 / 6.05 / 11.7 | 6.69 / 4.00 / 13.6 · 6.36 / 5.01 / 8.78 | 17.7 / 11.2 / 36.7 · 15.7 / 12.9 / 23.5 |
| slot pool via Allocator (256 B) | 6.23 / 2.04 / 3.53 | 4.42 / 3.68 / 3.39 | 16.3 / 10.4 / 7.76 |
| slot pool, direct (256 B) | 5.73 / 2.23 / 2.46 | 4.29 / 3.36 / 1.76 | 15.6 / 9.21 / 4.43 |

Threads: each thread allocates and frees 10,000 32-byte blocks 100 times (Flat_Pool: its own pool, reset per round);
ns per allocate+free of the slowest thread:

| allocator | mac-m2max 1 → 4 threads [M] | powerslabs [P] | ubuntu-laptop [L] |
|---|---|---|---|
| default heap | 25.4 → 37.9 (1.5×) | 26.2 → **904 (34.5×)** | 55.3 → **1889 (34.2×)** |
| rpmalloc (release flags), `THREAD_START` per thread | 8.28 → 8.63 (1.0×) | 5.58 → 5.72 (1.0×) | 13.4 → 17.0 (1.3×) |
| Flat_Pool per thread + reset | 4.42 → 4.93 (1.1×) | 4.16 → 4.31 (1.0×) | 10.1 → 12.6 (1.2×) |

What it implies:
- **Bump allocation + one reset** (temp, Flat_Pool, Pool) is the cheapest way to make many objects: 3–9 ns per
  allocation on the Mac and powerslabs (7–22 on the laptop) and nothing per free. When lifetimes line up (a frame, a
  request, a level), use it. `temp` was the fastest of the three everywhere.
- **A fixed-size free list is the fastest allocator with individual frees**: 0.7–2.9 ns per 32-byte allocate or free
  when called directly (256-byte batches cost more: 100,000 of them no longer fit in the caches). Going through
  `Allocator_Proc` (alloc/free via `context.allocator`) cost 1.4–2.3× for 32-byte blocks, 0.5–2.5 ns per call, and
  was still faster than any heap. Remember its locality cost after churn ("Lists, arrays and allocators").
- **The x64 default heap is slow for big batches of medium blocks** (71.9 ns per 256-byte allocation [P] vs 6.69 for
  rpmalloc) and **collapses under threads**: one heap behind a compare-and-swap spin lock taken on every allocate and
  free, no thread caches (read in `modules/Default_Allocator`), so four threads allocating at once made each call 34×
  slower. When spans empty out it keeps one per size class and unmaps the others (no span cache: its
  `heap_cache_insert` just unmaps), so a big freed batch has to be mapped and page-faulted again by the next one,
  which fits the slow 256-byte batches. macOS malloc stayed within 1.5× with 4 threads.
- **For threaded allocation-heavy code on x64, use the rpmalloc module or per-thread arenas**: both stayed at 1.0–1.3×.
  The rpmalloc heap is per thread (an `#add_context` field); POSIX threads never send `THREAD_START`, so each thread
  must call `rpmalloc_allocator_proc(.THREAD_START, 0, 0, null, null)` before allocating (and `.THREAD_STOP` at the
  end). Release flags matter: the module's defaults keep statistics and asserts on.
- macOS malloc churned slowly (40–57 ns per step vs 12–20 for rpmalloc on the same machine).

## How to measure on each platform

- Build like `-o` (`set_optimization(.VERY_OPTIMIZED)`, `stack_trace = false`); the suite's `build.jai` does it.
- Warm up once, take the median (and minimum) of at least 7 runs; time batches of thousands of operations with
  `current_time_monotonic()` and divide (a single short operation is below the clock's resolution).
- Keep every result live: sum into a checksum, print it, and verify the output (list sums, identical layouts,
  counts). Vary an input per pass (a "salt") so passes cannot be merged.
- **Verify the setup, not just the result**: our first shuffle used `for < i: values.count-1..1`, which runs zero times
  (a reverse loop is `for < i: low..high`), so the "shuffled" list was in order and as fast as an arena. a_locality
  now prints where the nodes landed; print such facts for anything you randomize.
- Linux: pin with `taskset -c <cpu>` to one performance core for single-threaded work and to P-cores only for threads
  (285K: CPUs 0–7; 265H: 0–5); E-cores have smaller L1s and shared L2s. Check `uptime` first. Laptops: the power
  profile changes absolute numbers (ubuntu-laptop ran "balanced").
- Linux counters: `perf stat -e cycles,instructions,cache-references,cache-misses,L1-dcache-load-misses,dTLB-load-misses
  taskset -c 2 ./prog` needs `kernel.perf_event_paranoid` ≤ 2 or root (paranoid was 3 on powerslabs, without perf
  installed, and 4 on ubuntu-laptop, where we ran it with sudo). `a_locality case=<row> size=<column>` runs one cell.
- macOS: no thread pinning and no `perf`; nothing equivalent was used here (Instruments has CPU counters; untested).
  Run when the machine is idle and record the load average (run.sh does).
- When a number looks too good, read the code: `xcrun objdump -d --no-show-raw-insn --disassemble-symbols=_name_<hex>
  prog` (macOS; find the symbol with `nm`), `objdump -d --no-show-raw-insn --disassemble=name_<hex> prog` (Linux), or
  `-output_ir` for LLVM IR in `.build/`. That is how the missing vectorization and the M2's fast list walks were
  checked.

## Checklist

1. Loops over arrays, not pointer graphs. Need links? Use indices into an array (smaller, relocatable).
2. Allocate what is walked together from one arena or pool, in walk order. After heavy churn, rebuild in order or
   iterate the storage instead of the links.
3. Split hot from cold fields; use SoA for loops that touch few fields; keep a hot struct (or AoS) for loops that use
   most of an element.
4. Don't assume `-o` vectorized a loop that stores through a view: check the disassembly; four floats per step through
   a 16-byte struct is a working fallback in 0.2.032.
5. Order struct members large to small; check with `size_of` and member offsets (examples 30, 49); `#no_padding` is
   not packing.
6. Per-thread hot data: pad to 128 bytes (Apple needs it; Intel is fine with 64); allocate padded arrays with
   `NewArray(n, T, alignment = 128)`; on Apple, `#import "Thread"()(CACHE_LINE_SIZE=128);`. Better still: work in
   locals and publish once.
7. Shared counters and locks are contention: shard per thread and combine; batch updates.
8. Threaded allocation on x64: not the default heap. rpmalloc (with `THREAD_START` per thread and release flags) or a
   Flat_Pool/temp per thread.
9. Misaligned loads are cheap in streaming loops; avoid them in latency-bound chains (line crossings 2.5×+ on Intel,
   16 KiB page crossings 10× on the M2); atomics must be naturally aligned.
10. Measure: `-o` build, warm-up, median of 7+, checksums, verified setup, pinned on Linux, disassembly when surprised.
