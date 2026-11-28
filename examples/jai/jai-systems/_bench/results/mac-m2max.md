# Cache and layout benchmarks: mac-m2max

- Date: 27 Nov 2026 21:08 MST
- CPU: Apple M2 Max; 8 P + 4 E cores
- Caches (sysctl): line 128 B; P-core L1d 128 KiB, L2 16 MiB per 4 P-cores; E-core L1d 64 KiB, L2 4 MiB; page 16384 B
- OS: macOS 26.6.2 (25G83), 96 GiB RAM
- Pinning: none (macOS has no user-level CPU pinning)
- Jai: beta 0.2.032
- Build: build.jai = set_optimization(.VERY_OPTIMIZED) + stack_trace = false (what `jai -o` sets)
- Method: one warm-up run, then the median (and min) of the timed runs; every kernel feeds a printed checksum
- Load average at start: 3.38 3.53 3.88

### a. Locality: ns per element, median of 7 runs (min)

Node = 16 bytes (next pointer + s64). A column's size is n nodes * 16 bytes; the s64 array and the 8-byte index nodes take half of that. Each timed run visits at least 4000000 elements.

| case | 32 KiB (n = 2048) | 1 MiB (n = 65536) | 8 MiB (n = 524288) | 32 MiB (n = 2097152) | 128 MiB (n = 8388608) |
|---|---|---|---|---|---|
| array of s64 | 0.16 (0.16) | 0.16 (0.15) | 0.16 (0.16) | 0.16 (0.16) | 0.16 (0.16) |
| index list in an array | 0.40 (0.34) | 0.35 (0.31) | 0.38 (0.32) | 0.39 (0.37) | 0.56 (0.38) |
| list, Flat_Pool | 0.33 (0.32) | 0.86 (0.84) | 0.34 (0.34) | 0.42 (0.41) | 0.53 (0.50) |
| list, heap in order | 0.95 (0.93) | 0.88 (0.86) | 0.56 (0.51) | 0.66 (0.60) | 0.76 (0.72) |
| list, heap + mixed sizes between | 0.95 (0.94) | 0.98 (0.93) | 1.03 (0.95) | 1.10 (1.07) | 1.19 (1.15) |
| list, heap + same size between | 0.88 (0.67) | 1.10 (1.04) | 0.88 (0.83) | 1.15 (1.07) | 1.08 (1.04) |
| list, heap churned | 0.95 (0.94) | 3.60 (3.49) | 4.32 (4.23) | 24.2 (22.2) | 48.4 (47.0) |
| list, slot pool churned | 0.94 (0.91) | 3.56 (3.50) | 4.23 (4.08) | 16.7 (15.1) | 32.6 (30.8) |
| slot pool scan (after churn) | 0.51 (0.48) | 0.53 (0.51) | 0.53 (0.52) | 0.50 (0.49) | 0.55 (0.52) |
| Bucket_Array scan | 0.49 (0.48) | 0.50 (0.49) | 0.53 (0.47) | 0.53 (0.52) | 0.54 (0.53) |
| list, shuffled | 0.94 (0.89) | 5.74 (5.72) | 7.91 (7.33) | 43.7 (41.5) | 105 (103) |

Every structure summed to n(n+1)/2: true. Checksum 3386290277539840.

Where the list nodes ended up, per size: share of steps to the next 16 bytes / share of steps backwards / 64-byte line changes per node (0.25 = four nodes per line, 1 = a new line at every node).

| list | 32 KiB (n = 2048) | 1 MiB (n = 65536) | 8 MiB (n = 524288) | 32 MiB (n = 2097152) | 128 MiB (n = 8388608) |
|---|---|---|---|---|---|
| list, Flat_Pool | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 |
| list, heap in order | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 | 1.00 / 0.00 / 0.25 |
| list, heap + mixed sizes between | 0.85 / 0.00 / 0.29 | 0.84 / 0.00 / 0.29 | 0.84 / 0.00 / 0.29 | 0.84 / 0.00 / 0.29 | 0.84 / 0.00 / 0.29 |
| list, heap + same size between | 0.00 / 0.00 / 0.50 | 0.00 / 0.00 / 0.50 | 0.00 / 0.00 / 0.50 | 0.00 / 0.00 / 0.50 | 0.00 / 0.00 / 0.50 |
| list, heap churned | 0.26 / 0.37 / 0.81 | 0.25 / 0.38 / 0.81 | 0.25 / 0.37 / 0.81 | 0.25 / 0.37 / 0.81 | 0.25 / 0.38 / 0.81 |
| list, slot pool churned | 0.25 / 0.37 / 0.81 | 0.25 / 0.37 / 0.81 | 0.25 / 0.38 / 0.81 | 0.25 / 0.38 / 0.81 | 0.25 / 0.37 / 0.81 |
| list, shuffled | 0.00 / 0.50 / 1.00 | 0.00 / 0.50 / 1.00 | 0.00 / 0.50 / 1.00 | 0.00 / 0.50 / 1.00 | 0.00 / 0.50 / 1.00 |

Load average after a_locality: 4.84 3.88 4.00

### b. AoS vs SoA vs hot/cold: ns per element, median of 7 runs (min)

Particle = 64 bytes (16 fields). Column = size of the AoS array (n particles * 64 bytes). Each timed run processes at least 4000000 elements.

**x += vx*dt (8 of 64 bytes)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.33 (0.31) | 0.91 (0.90) | 0.91 (0.89) | 0.96 (0.91) | 1.25 (1.16) |
| SoA | 0.35 (0.34) | 0.43 (0.40) | 0.32 (0.32) | 0.44 (0.42) | 0.47 (0.47) |
| hot/cold | 0.34 (0.33) | 0.45 (0.43) | 0.46 (0.44) | 0.47 (0.46) | 0.50 (0.49) |
| SoA, 4 floats per step | 0.09 (0.09) | 0.08 (0.08) | 0.11 (0.11) | 0.13 (0.13) | 0.15 (0.15) |

**sum of id (4 bytes, cold)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.27 (0.27) | 0.62 (0.61) | 0.65 (0.61) | 0.91 (0.90) | 1.09 (1.05) |
| SoA | 0.12 (0.12) | 0.12 (0.11) | 0.12 (0.12) | 0.12 (0.12) | 0.12 (0.12) |
| hot/cold | 0.28 (0.27) | 0.38 (0.37) | 0.40 (0.39) | 0.50 (0.43) | 0.69 (0.66) |

**pos += vel*dt (24 bytes)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.52 (0.50) | 1.08 (1.04) | 1.11 (1.10) | 1.15 (1.12) | 1.27 (1.20) |
| SoA | 0.76 (0.74) | 0.95 (0.89) | 0.95 (0.95) | 1.30 (1.29) | 1.39 (1.31) |
| hot/cold | 0.53 (0.51) | 0.66 (0.66) | 0.69 (0.62) | 0.70 (0.69) | 0.72 (0.69) |

**all 8 floats -> out[] (32 bytes)**

| layout | 32 KiB (n = 512) | 1 MiB (n = 16384) | 8 MiB (n = 131072) | 32 MiB (n = 524288) | 128 MiB (n = 2097152) |
|---|---|---|---|---|---|
| AoS | 0.80 (0.79) | 0.79 (0.76) | 0.83 (0.80) | 1.15 (1.12) | 1.20 (1.18) |
| SoA | 0.93 (0.90) | 1.22 (1.21) | 1.38 (1.35) | 2.41 (2.37) | 2.52 (2.45) |
| hot/cold | 0.79 (0.74) | 0.80 (0.79) | 0.84 (0.82) | 1.11 (1.06) | 1.11 (1.06) |

All three layouts ended with identical data: true. Checksum 83219200010830.

Load average after b_aos_soa: 4.84 3.88 4.00

### d. Alignment

**Dependent 8-byte loads at an offset inside 16 KiB blocks (4 blocks: L1), ns per load, median of 7 runs (min)**

| offset | ns per load | crosses |
|---|---|---|
| 0 | 0.95 (0.95) | nothing (aligned) |
| 4 | 1.25 (1.24) | nothing (misaligned inside a line) |
| 60 | 1.26 (1.25) | a 64-byte line |
| 124 | 1.26 (1.25) | a 64- and a 128-byte line |
| 4092 | 1.25 (1.23) | a 4 KiB page (and lines) |
| 16380 | 9.76 (9.66) | a 16 KiB page (and lines) |

**Summing / incrementing every u64 of a buffer: ns per u64, aligned (offset 0) vs offset 4**

| buffer | sum, offset 0 | sum, offset 4 | += 1, offset 0 | += 1, offset 4 |
|---|---|---|---|---|
| 16 KiB | 0.23 (0.21) | 0.22 (0.22) | 0.37 (0.36) | 0.37 (0.33) |
| 128 MiB | 0.23 (0.22) | 0.23 (0.22) | 0.46 (0.45) | 0.47 (0.47) |

**Arrays of {u8, u64, u8}: summing b, ns per element**

| layout | 1024 elements | 4000000 elements |
|---|---|---|
| padded (24 bytes) | 0.22 (0.21) | 0.43 (0.41) |
| reordered (16 bytes) | 0.22 (0.22) | 0.29 (0.28) |
| #no_padding (17 bytes) | 0.22 (0.22) | 0.30 (0.29) |

Checksum 3730488501417086884.

Load average after d_alignment: 4.77 3.88 4.00

### e. Allocator speed (one thread): ns per operation, median of 7 runs (min)

Default allocator here: "Jai wrapper for C’s malloc/free/realloc functions.". Batch: 100000 blocks allocated, then freed in the same order (bump allocators: one reset, divided by 100000). Churn: 10000 live blocks, 1000000 steps of free-random + allocate.

**32 bytes**

| allocator | batch: allocate | batch: free / reset | churn: free + allocate |
|---|---|---|---|
| default heap | 12.7 (12.6) | 13.0 (12.6) | 39.9 (39.5) |
| temp + reset | 3.08 (3.01) | one reset: 41.0 ns in all | n/a (no reuse) |
| Flat_Pool + reset | 4.69 (4.54) | one reset: 42.0 ns in all | n/a (no reuse) |
| Pool + reset | 5.13 (5.04) | one reset: 0.00 ns in all | n/a (no reuse) |
| rpmalloc (release flags) | 4.26 (4.15) | 4.34 (4.14) | 13.9 (13.5) |
| slot pool (via Allocator) | 2.26 (2.15) | 1.27 (1.24) | 3.43 (3.15) |
| slot pool, direct calls | 1.09 (0.97) | 0.71 (0.69) | 2.26 (2.06) |

**256 bytes**

| allocator | batch: allocate | batch: free / reset | churn: free + allocate |
|---|---|---|---|
| default heap | 13.5 (13.0) | 11.1 (10.9) | 44.4 (43.6) |
| temp + reset | 3.92 (3.89) | one reset: 0.00 ns in all | n/a (no reuse) |
| Flat_Pool + reset | 5.87 (5.40) | one reset: 42.0 ns in all | n/a (no reuse) |
| Pool + reset | 5.94 (5.59) | one reset: 42.0 ns in all | n/a (no reuse) |
| rpmalloc (release flags) | 6.13 (5.64) | 4.31 (4.14) | 19.8 (19.0) |
| slot pool (via Allocator) | 6.23 (5.40) | 2.04 (1.83) | 3.53 (3.43) |
| slot pool, direct calls | 5.73 (4.88) | 2.23 (1.75) | 2.46 (2.36) |

**mixed 16..512 bytes**

| allocator | batch: allocate | batch: free / reset | churn: free + allocate |
|---|---|---|---|
| default heap | 24.2 (19.1) | 21.6 (21.1) | 56.6 (56.3) |
| temp + reset | 5.05 (4.05) | one reset: 42.0 ns in all | n/a (no reuse) |
| Flat_Pool + reset | 5.77 (5.41) | one reset: 0.00 ns in all | n/a (no reuse) |
| Pool + reset | 7.75 (7.02) | one reset: 0.00 ns in all | n/a (no reuse) |
| rpmalloc (release flags) | 7.12 (6.62) | 6.05 (5.84) | 11.7 (11.2) |

Every block kept its contents until freed: true. Checksum 39901461877180.

Load average after e_alloc_speed: 4.71 3.88 4.00

### c. False sharing and contention: ns per increment per thread, median of 7 runs (min); slowdown vs own line

Each thread does 20000000 increments; the slowest thread's loop time counts. Counter block 128-byte aligned: true.

**plain (load, add, store) increments of a thread's own counter**

| layout | 1 thread | 2 threads | 4 threads |
|---|---|---|---|
| own line (pad 128) | 2.16 (2.13) | 2.10 (2.09) = 1.0x | 2.20 (2.16) = 1.0x |
| pad 64 | 2.12 (2.09) | 2.12 (2.10) = 1.0x | 2.21 (2.17) = 1.0x |
| adjacent (8 bytes apart) | 2.11 (2.08) | 2.19 (2.13) = 1.0x | 2.36 (2.30) = 1.1x |
| local, publish once | 0.22 (0.21) | 0.22 (0.21) = 0.1x | 0.24 (0.23) = 0.1x |

**atomic_add increments of a thread's own counter**

| layout | 1 thread | 2 threads | 4 threads |
|---|---|---|---|
| own line (pad 128) | 4.83 (4.80) | 4.76 (4.74) = 1.0x | 4.93 (4.86) = 1.0x |
| pad 64 | 4.82 (4.80) | 8.23 (7.59) = 1.7x | 8.14 (7.34) = 1.7x |
| adjacent (8 bytes apart) | 4.82 (4.77) | 17.4 (16.4) = 3.7x | 77.3 (73.5) = 15.7x |
| one shared atomic | 4.81 (4.75) | 17.8 (16.2) = 3.7x | 80.0 (73.3) = 16.2x |

All counts correct: true.

Load average after c_false_sharing: 5.66 4.24 4.12

### e. Allocator speed with threads: ns per allocate+free of 32 bytes, per thread (slowest thread), median of 7 runs (min)

Each thread: 100 rounds of allocating 10000 blocks and freeing them (Flat_Pool: its own pool, reset per round).

| allocator | 1 thread | 4 threads | slowdown |
|---|---|---|---|
| default heap | 25.4 (24.5) | 37.9 (37.6) | 1.5x |
| rpmalloc (release flags) | 8.28 (8.16) | 8.63 (8.39) | 1.0x |
| Flat_Pool per thread + reset | 4.42 (4.33) | 4.93 (4.62) | 1.1x |

Every block kept its contents until freed: true.

Load average after e_alloc_speed: 5.66 4.24 4.12

