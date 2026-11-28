# Cache and layout benchmarks: powerslabs

- Date: 27 Nov 2026 21:01 MST
- CPU: Intel(R) Core(TM) Ultra 9 285K, 24 CPUs
- Caches (sysfs, CPU 2): line 64 B; L1d 48K, L2 3072K, L3 36864K; page 4096 B
- OS: Obarun Linux, kernel 7.2.10-hardened1-3-hardened, 125 GiB RAM
- Pinning: single-thread benchmarks `taskset -c 2`, threaded `taskset -c 0-7` (thread counts: 2 4 8; allocator test: 4)
- Jai: beta 0.2.032
- Build: build.jai = set_optimization(.VERY_OPTIMIZED) + stack_trace = false (what `jai -o` sets)
- Method: one warm-up run, then the median (and min) of the timed runs; every kernel feeds a printed checksum
- Load average at start: 0.11, 0.08, 0.04

### a. Locality: ns per element, median of 7 runs (min)

Node = 16 bytes (next pointer + s64). A column's size is n nodes * 16 bytes; the s64 array and the 8-byte index nodes take half of that. Each timed run visits at least 4000000 elements.

| case | 32 KiB (n = 2048) | 1 MiB (n = 65536) | 8 MiB (n = 524288) | 32 MiB (n = 2097152) | 128 MiB (n = 8388608) |
|---|---|---|---|---|---|
| array of s64 | 0.05 (0.05) | 0.09 (0.09) | 0.14 (0.12) | 0.15 (0.15) | 0.27 (0.27) |
| index list in an array | 0.91 (0.91) | 0.91 (0.91) | 0.91 (0.91) | 0.92 (0.92) | 1.58 (1.57) |
| list, Flat_Pool | 0.73 (0.73) | 0.73 (0.73) | 0.74 (0.74) | 1.30 (1.28) | 2.35 (2.31) |
| list, heap in order | 0.73 (0.73) | 0.77 (0.77) | 0.76 (0.75) | 1.34 (1.31) | 2.36 (2.35) |
| list, heap + mixed sizes between | 0.73 (0.73) | 0.86 (0.86) | 0.86 (0.86) | 1.56 (1.55) | 1.84 (1.83) |
| list, heap + same size between | 0.88 (0.88) | 0.83 (0.83) | 0.87 (0.86) | 1.36 (1.27) | 1.32 (1.30) |
| list, heap churned | 0.96 (0.95) | 2.86 (2.86) | 7.57 (7.57) | 14.7 (14.6) | 50.6 (50.6) |
| list, slot pool churned | 0.73 (0.73) | 2.83 (2.82) | 7.55 (7.54) | 14.7 (14.6) | 50.6 (50.5) |
| slot pool scan (after churn) | 0.23 (0.22) | 0.29 (0.28) | 0.36 (0.36) | 0.77 (0.74) | 0.72 (0.72) |
| Bucket_Array scan | 0.25 (0.25) | 0.30 (0.30) | 0.39 (0.38) | 0.93 (0.92) | 1.26 (1.25) |
| list, shuffled | 0.73 (0.73) | 4.15 (4.15) | 13.6 (13.5) | 27.0 (26.9) | 102 (102) |

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

Load average after a_locality: 0.36, 0.14, 0.06

### b. AoS vs SoA vs hot/cold: ns per element, median of 7 runs (min)

Particle = 64 bytes (16 fields). Column = size of the AoS array (n particles * 64 bytes). Each timed run processes at least 4000000 elements.

**x += vx*dt (8 of 64 bytes)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.20 (0.20) | 0.64 (0.64) | 1.38 (1.38) | 1.54 (1.52) | 2.88 (2.78) |
| SoA | 0.17 (0.17) | 0.19 (0.19) | 0.22 (0.21) | 0.23 (0.23) | 0.25 (0.25) |
| hot/cold | 0.20 (0.20) | 0.33 (0.33) | 0.37 (0.37) | 0.47 (0.46) | 1.23 (1.17) |
| SoA, 4 floats per step | 0.06 (0.05) | 0.07 (0.07) | 0.09 (0.09) | 0.12 (0.12) | 0.16 (0.16) |

**sum of id (4 bytes, cold)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.20 (0.20) | 0.34 (0.34) | 1.20 (1.20) | 1.72 (1.71) | 3.03 (2.82) |
| SoA | 0.08 (0.08) | 0.07 (0.07) | 0.08 (0.08) | 0.08 (0.08) | 0.11 (0.11) |
| hot/cold | 0.20 (0.20) | 0.25 (0.25) | 0.69 (0.69) | 0.80 (0.80) | 1.72 (1.68) |

**pos += vel*dt (24 bytes)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.28 (0.28) | 0.72 (0.72) | 1.36 (1.35) | 1.87 (1.87) | 3.25 (3.16) |
| SoA | 0.55 (0.55) | 0.62 (0.62) | 0.72 (0.72) | 0.80 (0.80) | 1.20 (1.19) |
| hot/cold | 0.28 (0.28) | 0.55 (0.55) | 0.58 (0.58) | 0.62 (0.62) | 1.62 (1.49) |

**all 8 floats -> out[] (32 bytes)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.74 (0.74) | 0.98 (0.98) | 1.34 (1.33) | 2.45 (2.44) | 2.69 (2.61) |
| SoA | 0.74 (0.74) | 0.74 (0.74) | 0.74 (0.74) | 0.75 (0.75) | 1.04 (1.00) |
| hot/cold | 0.74 (0.74) | 0.87 (0.87) | 1.20 (1.20) | 2.24 (2.23) | 2.39 (2.35) |

All three layouts ended with identical data: true. Checksum 83219200010830.

Load average after b_aos_soa: 0.42, 0.16, 0.06

### d. Alignment

**Dependent 8-byte loads at an offset inside 16 KiB blocks (4 blocks: L1), ns per load, median of 7 runs (min)**

| offset | ns per load | crosses |
|---|---|---|
| 0 | 0.73 (0.73) | nothing (aligned) |
| 4 | 0.73 (0.73) | nothing (misaligned inside a line) |
| 60 | 2.00 (2.00) | a 64-byte line |
| 124 | 2.00 (2.00) | a 64- and a 128-byte line |
| 4092 | 2.00 (2.00) | a 4 KiB page (and lines) |
| 16380 | 2.00 (2.00) | a 16 KiB page (and lines) |

**Summing / incrementing every u64 of a buffer: ns per u64, aligned (offset 0) vs offset 4**

| buffer | sum, offset 0 | sum, offset 4 | += 1, offset 0 | += 1, offset 4 |
|---|---|---|---|---|
| 16 KiB | 0.19 (0.19) | 0.19 (0.19) | 0.19 (0.18) | 0.18 (0.18) |
| 128 MiB | 0.35 (0.35) | 0.34 (0.34) | 0.48 (0.48) | 0.49 (0.48) |

**Arrays of {u8, u64, u8}: summing b, ns per element**

| layout | 1024 elements | 4000000 elements |
|---|---|---|
| padded (24 bytes) | 0.19 (0.19) | 0.92 (0.85) |
| reordered (16 bytes) | 0.19 (0.19) | 0.97 (0.63) |
| #no_padding (17 bytes) | 0.19 (0.19) | 0.74 (0.70) |

Checksum 3730488501417086884.

Load average after d_alignment: 0.46, 0.17, 0.07

### e. Allocator speed (one thread): ns per operation, median of 7 runs (min)

Default allocator here: "stripped-down rpmalloc 1.4.4 intended as Default_Allocator". Batch: 100000 blocks allocated, then freed in the same order (bump allocators: one reset, divided by 100000). Churn: 10000 live blocks, 1000000 steps of free-random + allocate.

**32 bytes**

| allocator | batch: allocate | batch: free / reset | churn: free + allocate |
|---|---|---|---|
| default heap | 19.4 (19.2) | 9.41 (9.36) | 15.6 (15.5) |
| temp + reset | 2.78 (2.77) | one reset: 55.0 ns in all | n/a (no reuse) |
| Flat_Pool + reset | 4.12 (4.06) | one reset: 24.0 ns in all | n/a (no reuse) |
| Pool + reset | 5.67 (5.54) | one reset: 38.0 ns in all | n/a (no reuse) |
| rpmalloc (release flags) | 3.27 (3.26) | 2.39 (2.38) | 9.94 (9.80) |
| slot pool (via Allocator) | 1.53 (1.52) | 1.75 (1.73) | 2.65 (2.62) |
| slot pool, direct calls | 0.94 (0.91) | 1.21 (1.18) | 1.33 (1.32) |

**256 bytes**

| allocator | batch: allocate | batch: free / reset | churn: free + allocate |
|---|---|---|---|
| default heap | 71.9 (71.4) | 30.2 (29.6) | 22.7 (22.7) |
| temp + reset | 4.53 (4.49) | one reset: 150 ns in all | n/a (no reuse) |
| Flat_Pool + reset | 6.05 (6.00) | one reset: 30.0 ns in all | n/a (no reuse) |
| Pool + reset | 7.47 (6.96) | one reset: 102 ns in all | n/a (no reuse) |
| rpmalloc (release flags) | 6.69 (6.58) | 4.00 (3.95) | 13.6 (13.5) |
| slot pool (via Allocator) | 4.42 (4.31) | 3.68 (3.61) | 3.39 (3.32) |
| slot pool, direct calls | 4.29 (3.98) | 3.36 (2.92) | 1.76 (1.76) |

**mixed 16..512 bytes**

| allocator | batch: allocate | batch: free / reset | churn: free + allocate |
|---|---|---|---|
| default heap | 65.5 (65.1) | 34.1 (33.7) | 15.8 (15.8) |
| temp + reset | 6.05 (5.90) | one reset: 80.0 ns in all | n/a (no reuse) |
| Flat_Pool + reset | 7.43 (7.17) | one reset: 102 ns in all | n/a (no reuse) |
| Pool + reset | 9.21 (8.80) | one reset: 96.0 ns in all | n/a (no reuse) |
| rpmalloc (release flags) | 6.36 (6.12) | 5.01 (4.93) | 8.78 (8.69) |

Every block kept its contents until freed: true. Checksum 39901461877180.

Load average after e_alloc_speed: 0.46, 0.17, 0.07

### c. False sharing and contention: ns per increment per thread, median of 7 runs (min); slowdown vs own line

Each thread does 20000000 increments; the slowest thread's loop time counts. Counter block 128-byte aligned: true.

**plain (load, add, store) increments of a thread's own counter**

| layout | 1 thread | 2 threads | 4 threads | 8 threads |
|---|---|---|---|---|
| own line (pad 128) | 1.16 (1.12) | 1.16 (1.16) = 1.0x | 1.18 (1.18) = 1.0x | 1.19 (1.18) = 1.0x |
| pad 64 | 1.16 (1.12) | 1.16 (1.16) = 1.0x | 1.18 (1.18) = 1.0x | 1.18 (1.18) = 1.0x |
| adjacent (8 bytes apart) | 1.12 (1.12) | 1.47 (1.43) = 1.3x | 2.60 (2.27) = 2.2x | 3.19 (3.18) = 2.7x |
| local, publish once | 0.13 (0.12) | 0.13 (0.13) = 0.1x | 0.13 (0.13) = 0.1x | 0.13 (0.13) = 0.1x |

**atomic_add increments of a thread's own counter**

| layout | 1 thread | 2 threads | 4 threads | 8 threads |
|---|---|---|---|---|
| own line (pad 128) | 3.65 (3.64) | 3.65 (3.65) = 1.0x | 3.72 (3.71) = 1.0x | 3.72 (3.72) = 1.0x |
| pad 64 | 3.65 (3.64) | 3.65 (3.65) = 1.0x | 3.72 (3.71) = 1.0x | 3.72 (3.72) = 1.0x |
| adjacent (8 bytes apart) | 3.65 (3.64) | 20.5 (20.3) = 5.6x | 38.2 (34.1) = 10.3x | 75.3 (75.3) = 20.2x |
| one shared atomic | 3.65 (3.64) | 18.7 (17.3) = 5.1x | 38.2 (34.1) = 10.3x | 75.3 (75.2) = 20.2x |

All counts correct: true.

Load average after c_false_sharing: 3.11, 0.89, 0.32

### e. Allocator speed with threads: ns per allocate+free of 32 bytes, per thread (slowest thread), median of 7 runs (min)

Each thread: 100 rounds of allocating 10000 blocks and freeing them (Flat_Pool: its own pool, reset per round).

| allocator | 1 thread | 4 threads | slowdown |
|---|---|---|---|
| default heap | 26.2 (26.2) | 904 (875) | 34.5x |
| rpmalloc (release flags) | 5.58 (5.45) | 5.72 (5.69) | 1.0x |
| Flat_Pool per thread + reset | 4.16 (4.07) | 4.31 (4.22) | 1.0x |

Every block kept its contents until freed: true.

Load average after e_alloc_speed: 3.17, 0.97, 0.35

