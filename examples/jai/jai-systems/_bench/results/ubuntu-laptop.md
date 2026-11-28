# Cache and layout benchmarks: ubuntu-laptop

- Date: 27 Nov 2026 21:03 MST
- CPU: Intel(R) Core(TM) Ultra 7 265H, 16 CPUs
- Caches (sysfs, CPU 2): line 64 B; L1d 48K, L2 3072K, L3 24576K; page 4096 B
- OS: Ubuntu 26.10, kernel 7.3.0-10-generic, 61 GiB RAM
- Pinning: single-thread benchmarks `taskset -c 2`, threaded `taskset -c 0-5` (thread counts: 2 4 6; allocator test: 4)
- Jai: beta 0.2.032
- Build: build.jai = set_optimization(.VERY_OPTIMIZED) + stack_trace = false (what `jai -o` sets)
- Method: one warm-up run, then the median (and min) of the timed runs; every kernel feeds a printed checksum
- Load average at start: 0.17, 0.12, 0.05

### a. Locality: ns per element, median of 7 runs (min)

Node = 16 bytes (next pointer + s64). A column's size is n nodes * 16 bytes; the s64 array and the 8-byte index nodes take half of that. Each timed run visits at least 4000000 elements.

| case | 32 KiB (n = 2048) | 1 MiB (n = 65536) | 8 MiB (n = 524288) | 32 MiB (n = 2097152) | 128 MiB (n = 8388608) |
|---|---|---|---|---|---|
| array of s64 | 0.15 (0.15) | 0.21 (0.21) | 0.30 (0.30) | 0.38 (0.38) | 0.64 (0.63) |
| index list in an array | 1.01 (1.01) | 2.18 (2.18) | 2.19 (2.19) | 2.33 (2.32) | 3.65 (3.63) |
| list, Flat_Pool | 0.81 (0.80) | 1.75 (1.75) | 1.77 (1.77) | 3.85 (3.82) | 5.07 (5.04) |
| list, heap in order | 0.81 (0.80) | 1.84 (1.84) | 1.80 (1.80) | 3.96 (3.80) | 5.07 (5.05) |
| list, heap + mixed sizes between | 0.81 (0.81) | 2.06 (2.06) | 2.05 (2.04) | 3.97 (3.95) | 4.16 (4.15) |
| list, heap + same size between | 2.11 (2.11) | 2.00 (1.99) | 2.26 (2.25) | 2.65 (2.61) | 2.74 (2.69) |
| list, heap churned | 2.30 (2.29) | 6.85 (6.85) | 16.0 (15.9) | 79.6 (78.8) | 224 (219) |
| list, slot pool churned | 1.75 (1.75) | 6.78 (6.42) | 15.9 (15.7) | 79.4 (79.0) | 223 (221) |
| slot pool scan (after churn) | 0.54 (0.54) | 0.59 (0.59) | 0.82 (0.82) | 2.38 (2.25) | 1.66 (1.65) |
| Bucket_Array scan | 0.59 (0.59) | 0.62 (0.62) | 0.89 (0.89) | 2.64 (2.61) | 2.88 (2.87) |
| list, shuffled | 1.75 (1.75) | 8.80 (8.80) | 27.9 (27.9) | 173 (168) | 462 (458) |

Every structure summed to n(n+1)/2: true. Checksum 3386290277539840.

Where the list nodes ended up, per size: share of steps to the next 16 bytes / share of steps backwards / 64-byte line changes per node (0.25 = four nodes per line, 1 = a new line at every node).

| list | 32 KiB (n = 2048) | 1 MiB (n = 65536) | 8 MiB (n = 524288) | 32 MiB (n = 2097152) | 128 MiB (n = 8388608) |
|---|---|---|---|---|---|
| list, Flat_Pool | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 |
| list, heap in order | 1.00 / 0.00 / 0.25 | 0.94 / 0.04 / 0.29 | 0.99 / 0.00 / 0.26 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 |
| list, heap + mixed sizes between | 0.11 / 0.87 / 0.29 | 0.80 / 0.02 / 0.32 | 0.84 / 0.00 / 0.29 | 0.84 / 0.00 / 0.29 | 0.84 / 0.00 / 0.29 |
| list, heap + same size between | 0.00 / 0.07 / 0.57 | 0.00 / 0.03 / 0.52 | 0.00 / 0.00 / 0.50 | 0.00 / 0.00 / 0.50 | 0.00 / 0.00 / 0.50 |
| list, heap churned | 0.03 / 0.59 / 0.87 | 0.23 / 0.38 / 0.82 | 0.25 / 0.38 / 0.81 | 0.25 / 0.38 / 0.81 | 0.25 / 0.38 / 0.81 |
| list, slot pool churned | 0.25 / 0.37 / 0.81 | 0.25 / 0.37 / 0.81 | 0.25 / 0.38 / 0.81 | 0.25 / 0.38 / 0.81 | 0.25 / 0.37 / 0.81 |
| list, shuffled | 0.00 / 0.50 / 1.00 | 0.00 / 0.50 / 1.00 | 0.00 / 0.50 / 1.00 | 0.00 / 0.50 / 1.00 | 0.00 / 0.50 / 1.00 |

Load average after a_locality: 0.92, 0.39, 0.16

### b. AoS vs SoA vs hot/cold: ns per element, median of 7 runs (min)

Particle = 64 bytes (16 fields). Column = size of the AoS array (n particles * 64 bytes). Each timed run processes at least 4000000 elements.

**x += vx*dt (8 of 64 bytes)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.61 (0.60) | 1.55 (1.53) | 3.31 (3.31) | 3.91 (3.86) | 4.60 (4.56) |
| SoA | 0.52 (0.43) | 0.45 (0.45) | 0.52 (0.52) | 0.54 (0.54) | 0.62 (0.61) |
| hot/cold | 0.48 (0.47) | 0.80 (0.80) | 0.87 (0.87) | 1.31 (1.31) | 2.08 (2.06) |
| SoA, 4 floats per step | 0.13 (0.13) | 0.16 (0.16) | 0.21 (0.21) | 0.29 (0.29) | 0.53 (0.47) |

**sum of id (4 bytes, cold)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.48 (0.48) | 0.81 (0.81) | 2.80 (2.80) | 5.30 (5.03) | 6.03 (5.77) |
| SoA | 0.19 (0.19) | 0.17 (0.17) | 0.19 (0.19) | 0.25 (0.25) | 0.44 (0.41) |
| hot/cold | 0.49 (0.49) | 0.60 (0.60) | 1.64 (1.64) | 2.73 (2.61) | 3.65 (3.54) |

**pos += vel*dt (24 bytes)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.68 (0.67) | 1.72 (1.72) | 3.20 (3.19) | 5.38 (5.32) | 6.75 (6.55) |
| SoA | 1.31 (1.31) | 1.49 (1.49) | 1.92 (1.92) | 1.94 (1.93) | 2.29 (2.26) |
| hot/cold | 0.68 (0.68) | 1.31 (1.31) | 1.39 (1.39) | 1.71 (1.71) | 2.84 (2.80) |

**all 8 floats -> out[] (32 bytes)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 1.80 (1.79) | 2.36 (2.36) | 3.13 (3.12) | 7.36 (6.81) | 6.30 (6.21) |
| SoA | 1.79 (1.77) | 1.77 (1.77) | 1.77 (1.77) | 1.81 (1.81) | 2.14 (2.11) |
| hot/cold | 1.78 (1.77) | 2.08 (2.08) | 3.01 (3.01) | 5.85 (5.63) | 5.18 (5.15) |

All three layouts ended with identical data: true. Checksum 83219200010830.

Load average after b_aos_soa: 0.92, 0.39, 0.16

### d. Alignment

**Dependent 8-byte loads at an offset inside 16 KiB blocks (4 blocks: L1), ns per load, median of 7 runs (min)**

| offset | ns per load | crosses |
|---|---|---|
| 0 | 1.75 (1.75) | nothing (aligned) |
| 4 | 1.75 (1.75) | nothing (misaligned inside a line) |
| 60 | 4.80 (4.29) | a 64-byte line |
| 124 | 4.70 (4.25) | a 64- and a 128-byte line |
| 4092 | 4.44 (4.25) | a 4 KiB page (and lines) |
| 16380 | 4.31 (4.25) | a 16 KiB page (and lines) |

**Summing / incrementing every u64 of a buffer: ns per u64, aligned (offset 0) vs offset 4**

| buffer | sum, offset 0 | sum, offset 4 | += 1, offset 0 | += 1, offset 4 |
|---|---|---|---|---|
| 16 KiB | 0.45 (0.45) | 0.45 (0.45) | 0.44 (0.44) | 0.44 (0.44) |
| 128 MiB | 0.88 (0.71) | 0.73 (0.73) | 1.02 (1.02) | 1.03 (1.02) |

**Arrays of {u8, u64, u8}: summing b, ns per element**

| layout | 1024 elements | 4000000 elements |
|---|---|---|
| padded (24 bytes) | 0.46 (0.45) | 2.14 (2.00) |
| reordered (16 bytes) | 0.46 (0.45) | 1.44 (1.37) |
| #no_padding (17 bytes) | 0.46 (0.46) | 1.60 (1.58) |

Checksum 3730488501417086884.

Load average after d_alignment: 1.01, 0.43, 0.17

### e. Allocator speed (one thread): ns per operation, median of 7 runs (min)

Default allocator here: "stripped-down rpmalloc 1.4.4 intended as Default_Allocator". Batch: 100000 blocks allocated, then freed in the same order (bump allocators: one reset, divided by 100000). Churn: 10000 live blocks, 1000000 steps of free-random + allocate.

**32 bytes**

| allocator | batch: allocate | batch: free / reset | churn: free + allocate |
|---|---|---|---|
| default heap | 30.6 (30.0) | 20.3 (20.0) | 37.8 (37.6) |
| temp + reset | 6.72 (6.66) | one reset: 70.0 ns in all | n/a (no reuse) |
| Flat_Pool + reset | 10.1 (10.1) | one reset: 77.0 ns in all | n/a (no reuse) |
| Pool + reset | 13.6 (12.6) | one reset: 75.0 ns in all | n/a (no reuse) |
| rpmalloc (release flags) | 7.79 (7.77) | 5.72 (5.70) | 24.2 (24.0) |
| slot pool (via Allocator) | 4.75 (3.67) | 4.19 (4.10) | 7.29 (6.49) |
| slot pool, direct calls | 2.25 (2.16) | 2.86 (2.84) | 3.12 (3.11) |

**256 bytes**

| allocator | batch: allocate | batch: free / reset | churn: free + allocate |
|---|---|---|---|
| default heap | 122 (122) | 45.4 (44.9) | 54.7 (54.6) |
| temp + reset | 11.7 (11.6) | one reset: 166 ns in all | n/a (no reuse) |
| Flat_Pool + reset | 15.3 (15.2) | one reset: 63.0 ns in all | n/a (no reuse) |
| Pool + reset | 19.4 (18.8) | one reset: 121 ns in all | n/a (no reuse) |
| rpmalloc (release flags) | 17.7 (17.3) | 11.2 (10.6) | 36.7 (36.5) |
| slot pool (via Allocator) | 16.3 (14.9) | 10.4 (10.0) | 7.76 (7.24) |
| slot pool, direct calls | 15.6 (14.5) | 9.21 (9.04) | 4.43 (4.41) |

**mixed 16..512 bytes**

| allocator | batch: allocate | batch: free / reset | churn: free + allocate |
|---|---|---|---|
| default heap | 130 (128) | 48.9 (47.0) | 38.1 (38.0) |
| temp + reset | 17.3 (15.3) | one reset: 181 ns in all | n/a (no reuse) |
| Flat_Pool + reset | 17.5 (16.9) | one reset: 82.0 ns in all | n/a (no reuse) |
| Pool + reset | 21.6 (21.4) | one reset: 221 ns in all | n/a (no reuse) |
| rpmalloc (release flags) | 15.7 (15.5) | 12.9 (12.8) | 23.5 (23.1) |

Every block kept its contents until freed: true. Checksum 39901461877180.

Load average after e_alloc_speed: 1.01, 0.44, 0.18

### c. False sharing and contention: ns per increment per thread, median of 7 runs (min); slowdown vs own line

Each thread does 20000000 increments; the slowest thread's loop time counts. Counter block 128-byte aligned: true.

**plain (load, add, store) increments of a thread's own counter**

| layout | 1 thread | 2 threads | 4 threads | 6 threads |
|---|---|---|---|---|
| own line (pad 128) | 3.13 (3.09) | 3.51 (3.11) = 1.0x | 3.10 (3.08) = 1.0x | 2.78 (2.78) = 1.0x |
| pad 64 | 2.93 (2.77) | 3.23 (3.13) = 0.9x | 3.09 (3.08) = 1.0x | 2.79 (2.78) = 1.0x |
| adjacent (8 bytes apart) | 2.94 (2.77) | 3.98 (3.83) = 1.1x | 5.58 (5.43) = 1.8x | 6.84 (6.83) = 2.5x |
| local, publish once | 0.30 (0.29) | 0.34 (0.30) = 0.1x | 0.37 (0.30) = 0.1x | 0.30 (0.30) = 0.1x |

**atomic_add increments of a thread's own counter**

| layout | 1 thread | 2 threads | 4 threads | 6 threads |
|---|---|---|---|---|
| own line (pad 128) | 9.40 (9.36) | 9.37 (9.36) = 1.0x | 9.36 (8.77) = 1.0x | 8.78 (8.77) = 1.0x |
| pad 64 | 9.36 (9.32) | 9.37 (8.77) = 1.0x | 9.38 (8.78) = 1.0x | 8.78 (8.77) = 1.0x |
| adjacent (8 bytes apart) | 9.37 (9.33) | 36.6 (36.2) = 3.9x | 90.0 (86.8) = 9.6x | 138 (137) = 15.7x |
| one shared atomic | 9.37 (9.34) | 47.9 (41.7) = 5.1x | 87.9 (86.8) = 9.4x | 137 (136) = 15.6x |

All counts correct: true.

Load average after c_false_sharing: 4.12, 1.67, 0.66

### e. Allocator speed with threads: ns per allocate+free of 32 bytes, per thread (slowest thread), median of 7 runs (min)

Each thread: 100 rounds of allocating 10000 blocks and freeing them (Flat_Pool: its own pool, reset per round).

| allocator | 1 thread | 4 threads | slowdown |
|---|---|---|---|
| default heap | 55.3 (54.1) | 1889 (1848) | 34.2x |
| rpmalloc (release flags) | 13.4 (13.2) | 17.0 (13.4) | 1.3x |
| Flat_Pool per thread + reset | 10.1 (9.85) | 12.6 (10.1) | 1.2x |

Every block kept its contents until freed: true.

Load average after e_alloc_speed: 4.09, 1.79, 0.71

### Addendum: hardware counters for four lists at 128 MiB (perf stat, same machine, 27 Nov 2026)

`kernel.perf_event_paranoid` is 4 here, so perf ran under sudo. One `a_locality` cell per command (the `case=` and
`size=` arguments, same kernels as above), pinned to CPU 2:

    sudo perf stat -e cycles,instructions,cache-references,cache-misses,L1-dcache-load-misses,dTLB-load-misses \
        taskset -c 2 ./bin/a_locality case=<C> size=4

The counters cover the whole process, including building the structure, but the timed walks dominate: 8 walks
(1 warm-up + 7 timed) of 8,388,608 elements = 67.1 million visits. `cache-misses` counts last-level-cache misses.

| case (C) | ns per element | cycles | cache-references | cache-misses | L1-dcache-load-misses | dTLB-load-misses | elapsed |
|---|---|---|---|---|---|---|---|
| array of s64 (0) | 0.43 | 0.303 G | 11.0 M | 5.87 M | 5.11 M | 16.4 K | 0.086 s |
| list, Flat_Pool (2) | 5.07 | 1.70 G | 25.2 M | 22.0 M | 0.714 M | 38.1 K | 0.547 s |
| list, heap churned (6) | 225 | 12.9 G | 265 M | 154 M | 132 M | 50.8 M | 18.8 s |
| list, shuffled (10) | 463 | 18.3 G | 206 M | 167 M | 146 M | 77.0 M | 35.3 s |

Per visit: the Flat_Pool list misses the last-level cache 0.33 times and L1 0.011 times (the hardware prefetcher
brings the next lines in ahead of the walk) and nearly never misses the TLB; the churned list misses the last-level
cache 2.3 times, L1 2.0 times and the TLB 0.76 times; the shuffled list 2.5, 2.2 and 1.15 times (more than one miss
per visit: a TLB miss starts a page-table walk whose own loads miss too, and setup is included). The array's whole
run took 0.086 s, so its counters include a larger share of setup.
