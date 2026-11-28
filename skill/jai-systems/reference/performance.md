# Performance: build modes, checks, backends, layout, measured (deep dive)

Measured on Jai beta 0.2.032, 27 Nov 2026: **Mac** = MacBook Pro M2 Max (arm64, macOS 26.6, LLVM backend only),
**powerslabs** = Intel Core Ultra 9 285K (24 cores, Arch hardened kernel), **ubuntu-laptop** = Intel Core Ultra 7 265H
(16 cores, Ubuntu 26.10, a laptop: noisy). Examples: `examples/jai/jai-systems/28`–`34`. Sources:
`modules/Default_Metaprogram.jai` (flags), `modules/Compiler/Compiler.jai` (`Build_Options`, `set_optimization`),
`modules/Runtime_Support.jai` (check failure messages), `how_to/900_inline_assembly.jai`, `modules/Machine_X64.jai`,
`Bit_Operations.jai`, `SIMD.jai`, `Sort.jai`, `IntroSort.jai`, `RadixSort.jai`, `Hash.jai`, `xxHash/`, `meow_hash/`.

## What each flag sets (Default_Metaprogram + set_optimization, 0.2.032)

| Command | Optimization | array/cast/null checks | stack traces | LLVM extras |
|---|---|---|---|---|
| `jai f.jai` | none (`bitcode_optimization_setting = UNSET` → O0) | ON / FATAL / ON | ON | split modules (parallel, fast) |
| `jai f.jai -very_debug` | VERY_DEBUG (O0) | ON / FATAL / ON | ON | arithmetic overflow checks are commented out in `set_optimization`: still OFF |
| `jai f.jai -od` (`-optimized_debug`) | OPTIMIZED: O2, machine code DEFAULT | OFF | **ON** | tail calls, loop unrolling, no split modules |
| `jai f.jai -o` (`-optimized`) | VERY_OPTIMIZED: O3, machine code AGGRESSIVE | OFF | **OFF** | + loop and SLP vectorization |
| `-release` / `-release_debug` | same as `-o` / `-od` | | | warn since 0.2.026; use `-o` / `-od` |
| `-x64` | non-LLVM backend, x86-64 only | defaults | defaults | |
| `-no_inline` | bytecode inliner off (`enable_bytecode_inliner = false`) | | | |

- `set_optimization(*options, type, preserve_debug_info = true)` is the same helper for build.jai: `.DEBUG`,
  `.VERY_DEBUG`, `.OPTIMIZED`, `.VERY_OPTIMIZED`, `.OPTIMIZED_SMALL` (Os), `.OPTIMIZED_VERY_SMALL` (Oz). With
  `preserve_debug_info = false` it also drops debug info. It never touches `stack_trace`: Default_Metaprogram sets that
  for `-o` only. Frame pointers stay on (always on macOS).
- Individual fields: `array_bounds_check: enum {OFF, ON, ALWAYS}`, `cast_bounds_check: {OFF, NONFATAL, FATAL}`,
  `null_pointer_check: {OFF, ON}`, `arithmetic_overflow_check: {OFF, NONFATAL, FATAL}` (default OFF in every mode),
  `stack_trace`, `backend: {X64, LLVM}`, `llvm_options.*` (`enable_loop_vectorization`, `enable_slp_vectorization`,
  `disable_inlining`, `enable_split_modules`, `target_system_cpu`, `target_system_features`, `output_llvm_ir`),
  `x64_options.enable_register_allocation` (crashes, below), `dead_code_elimination`, `enable_bytecode_inliner`.
- Inside the program `BUILD :: #run get_build_options();` sees its own workspace's options (example 28: under `-o`
  backend LLVM, O3, all checks OFF, stack_trace false).

## The benchmark (own code; scratch `bench/bench.jai` + `bench/build.jai`)

Kernels: `dot` of two 4M float64 arrays; `sieve` of Eratosthenes to 10M (bool array); naive `matmul` 256×256 float64;
recursive `fib(30)` (call-heavy). Each kernel runs 9 times; median (and min) wall time with
`current_time_monotonic()`. Results are accumulated and printed so nothing is optimized away.

```jai
// build.jai: jai build.jai - <variant>   builds bench.jai as ./bench_<variant>
#import "Basic";
#import "Compiler";
#run {
    set_build_options_dc(.{do_output = false});
    args := get_build_options().compile_time_command_line;
    variant := ifx args.count then args[0] else "debug";
    w := compiler_create_workspace(variant);
    o := get_build_options(w);
    o.output_executable_name = tprint("bench_%", variant);
    o.text_output_flags = .OUTPUT_TIMING_INFO;
    if variant == {
      case "debug";
      case "debug_nochecks";   o.array_bounds_check = .OFF; o.cast_bounds_check = .OFF; o.null_pointer_check = .OFF;
      case "debug_nostack";    o.stack_trace = false;
      case "od";               set_optimization(*o, .OPTIMIZED);
      case "o";                set_optimization(*o, .VERY_OPTIMIZED); o.stack_trace = false;
      case "o_checks";         set_optimization(*o, .VERY_OPTIMIZED); o.stack_trace = false; o.array_bounds_check = .ON;
      case "o_stack";          set_optimization(*o, .VERY_OPTIMIZED);
      case "x64";              o.backend = .X64;
      case "x64_nochecks";     o.backend = .X64; o.array_bounds_check = .OFF; o.cast_bounds_check = .OFF; o.null_pointer_check = .OFF;
      case "x64_regalloc";     o.backend = .X64; o.x64_options.enable_register_allocation = true;
      case "x64_o";            o.backend = .X64; set_optimization(*o, .VERY_OPTIMIZED); o.stack_trace = false;
      case; print("unknown variant %\n", variant); return;
    }
    set_build_options(o, w);
    add_build_file("bench.jai", w);
}
```

The timing helper in bench.jai is the same macro pattern as example 34 (`#expand` + `#insert body` of a `#code`
argument, quick_sort the samples, take the middle one).

## Results: median ms (dot / sieve / matmul / fib30)

| Variant | Mac M2 Max | powerslabs 285K | ubuntu-laptop 265H |
|---|---|---|---|
| debug | 17.8 / 112.7 / 108.0 / 11.6 | 9.6 / 65.4 / 44.7 / 7.2 | 11.6 / 158.7* / 109.4 / 16.8 |
| debug, bounds/cast/null checks off | 15.3 / 91.9 / 84.1 / 11.4 | 8.8 / 50.0 / 37.5 / 6.9 | 9.8 / 119.1* / 92.8 / 16.9 |
| debug, stack traces off | 18.2 / 113.6 / 108.8 / **5.6** | 10.3 / 73.6 / 45.7 / **2.7** | — |
| `-od` | 3.9 / 16.9 / 12.6 / 7.5 | 3.5 / 18.0 / 10.1 / 5.1 | 5.6 / 45.6 / 24.2 / 11.7 |
| `-o` | 3.8 / 13.1 / 12.7 / **3.2** | 3.4 / 18.3 / 10.1 / **2.2** | 5.5 / 45.8 / 24.2 / **5.1** |
| `-o` + array bounds checks ON | 3.8 / 17.1 / 14.2 / 3.0 | 4.7 / 18.0 / 10.4 / 2.2 | 6.8 / 45.3 / 25.0 / 5.1 |
| `-o` but stack traces ON | 3.8 / 12.9 / 12.9 / 7.5 | 3.3 / 17.5 / 9.7 / 5.0 | — |
| `-x64` (debug defaults) | n/a | 9.1 / 59.9 / 45.5 / 14.6 | 20.0 / 142.7 / 97.3 / 31.8 |
| `-x64`, checks off | n/a | 9.3 / 50.5 / 37.8 / 13.3 | 19.6 / 120.3 / 91.1 / 28.2 |
| `-x64` + `set_optimization(.VERY_OPTIMIZED)`, no stack traces | n/a | 9.1 / 50.9 / 37.9 / 9.5 | 19.5 / 123.6 / 91.2 / 19.7 |
| `-x64` + `enable_register_allocation` | n/a | **segfault** (exit 139, even a hello world) | — |

`*` = large spread (min 99.8 / 55.0 ms): the laptop throttles. A rerun on the Mac while other jobs loaded it
(load average 43) gave debug sieve 183 ms and -od fib 36 ms: **compare variants within one quiet session** and
report medians with their spread.

### Compile time (wall clock, bench.jai + Basic + Sort, ~11k lines)

| Variant | Mac | powerslabs | ubuntu-laptop |
|---|---|---|---|
| debug (LLVM, split modules) | 0.19 s (LLVM 0.12 s) | 0.17 s (LLVM 0.09–0.21 s) | 0.42 s |
| `-od` | 0.68 s (LLVM 0.52 s) | 0.73 s (LLVM 0.60 s) | 1.53 s |
| `-o` | 0.60 s (LLVM 0.44 s) | 0.72 s (LLVM 0.57 s) | 1.49 s |
| `-x64` | n/a | 0.13 s (x64 backend 0.002 s, front end 0.03 s) | 0.31 s |

A hello-world-sized program: 0.12–0.18 s debug on Mac/powerslabs, 0.09 s with `-x64` on powerslabs.

### What the numbers say

- `-o` is 2–9× faster than debug on loops (Mac 4.7–8.6×, powerslabs 2.8–4.4×, ubuntu-laptop 2.1–4.5×) and 3.3–3.6× on
  calls. `-od` equals `-o` on loops but is 2.3× slower on
  fib because it keeps the stack-trace bookkeeping (a node pushed and popped per call).
- **Stack traces cost 2–2.7× on call-heavy code**, nothing measurable on loops (debug vs debug-no-stack; -o vs
  -o-with-stack). Turn them off for performance builds; keep them in debug builds where they power assert reports,
  the memory debugger and `print_stack_trace`.
- **Checks**: in debug builds the bounds/cast/null checks add 9–31% run time on the loop kernels (none on fib).
  Array bounds checks alone under -o add 0–38% (Mac sieve +31%, powerslabs dot +38%, ubuntu-laptop dot +24%, the rest
  within noise). Keep them on in debug, remove per hot loop with `#no_abc` when a profile shows them.
- The **x64 backend** builds the code ~50–100× faster than LLVM (2–3 ms instead of 90–600 ms for the backend part),
  but its code is about as fast as LLVM -O0 on loops and 2× slower on calls; `set_optimization` only turns its checks
  off. Use it for edit-compile-run iteration on x86-64, never for shipping or benchmarking. Not available on arm64:
  "Error: The x64 backend supports only x64 CPUs but the CPU target was set to ARM64 (4)".
- The bundle's own advice in `set_optimization` comments: debug builds stay at O0 because O1 made LLVM much slower to
  compile and hid `context` in debuggers.

### Hashes and sorts (scratch `bench/bench2.jai`, built with `-o`, median of 7)

| Routine | Mac | powerslabs |
|---|---|---|
| `Hash.fnv1a_hash(data, 64 MiB)` | 83.9 ms (0.8 GB/s) | 49 ms (1.4 GB/s) |
| `xxHash.native_XXH64` (pure Jai, v0.7 port) | 4.9 ms (13.8 GB/s) | 5.4 ms (12.5 GB/s) |
| `xxHash.native_XXH32` | 14.3 ms (4.7 GB/s) | 8.7 ms (7.7 GB/s) |
| `meow_hash.MeowHash` (x64 AES `#asm`) | n/a on arm64 | 2.5 ms (26.5 GB/s) |
| `Sort.quick_sort` 1M u32 (comparison proc) | 102.7 ms | 81.7 ms |
| `IntroSort.intro_sort` 1M u32 | 83.5 ms | 69.5 ms |
| `RadixSort` (`sort(*radix, array)`: computes ranks, data unchanged) | 9.1 ms | 8.7 ms |

`Hash.get_hash`/`fnv1a_hash` are fine for hash tables of small keys, not for bulk data. `RadixSort` returns a
permutation (`rank(*radix, i)`, `reorder`), not a sorted array. `quick_sort` also has a `(T) -> key` overload and,
since 0.2.031, a version with a user-data pointer.

## Local control

- `#no_abc` / `#no_aoc` (no array bounds / no arithmetic overflow checks): after a procedure header
  (`hash :: (s: string) -> u32 #no_aoc { }`), before a block (`#no_aoc { x += 1; }`), after a for header
  (`for i: 0..n-1 #no_abc { }`). Example 29 builds with `arithmetic_overflow_check = .FATAL` and shows both forms.
- Casts: `cast(u8) x` is range-checked in debug ("Cast bounds check failed.  Number must be in [0, 255]; it was 302.");
  `cast,trunc(u8) x` keeps the low bits on purpose; `cast,no_check(u8) x` skips the check; `xx x` is checked like
  `cast` (example 37).
- Inlining: `inline` on a declaration (`twice :: inline (x: int) -> int {...}`) or at a call site (`inline f(x)`),
  `no_inline` likewise; `-no_inline` disables the bytecode inliner for the whole program (for debugging). LLVM's own
  inliner is off in debug (`disable_inlining = debug`) and on in -od/-o.
- Parameter passing (how_to/250): values up to 8 bytes by value; bigger ones (structs, strings, Any, arrays) "maybe by
  reference": the callee must not modify them (copy first) and you may not rely on either behaviour. Return values
  are written straight into the caller's storage. So passing structs by value is not the copy cost it is in C.

## Data layout

- Fields are laid out in declaration order with natural alignment: `{u8, u64, u8}` is 24 bytes, `{u64, u8, u8}` 16.
- `#align N` on a struct member (`value: int #align 64;` makes the struct 64 bytes: per-thread counters on separate
  cache lines) or on a variable (`scratch: [256] u8 #align 64;`, global or local).
- **`#no_padding` (0.2.032) only removes trailing padding.** For `{u8, u64, u8} #no_padding` the members stay at
  offsets 0, 8, 16 (type_info and real memory agree), `size_of` becomes 17 and arrays use a stride of 17, so element 1's
  u64 sits at byte 25: misaligned. It is not a packed-struct feature; use it only on structs that are already packed
  (the bundle uses it for file headers). Example 30 prints the offsets.
- Struct-of-arrays: write it by hand (one array per hot field) or generate it with metaprogramming
  (`modules/Soa.jai` is a small experimental generator, see jai-metaprogramming). Keep hot loops over contiguous
  arrays; how_to/200 explains why pointer-chasing structures are slow on modern CPUs.

## SIMD, #asm, CPU features

- `modules/SIMD.jai` is a **prototype** of a portable SIMD API: `SIMD_Array(count, T)` with element-wise operators
  (`+ - * /` with a scalar, comparisons), `min/max`, `horizontal_add/sum`, `load/store`, `get_mask`. The bodies are
  scalar loops: no guaranteed speedup (LLVM may vectorize them under `-o`). Verified it computes correctly.
- Real vector code today: write loops that LLVM vectorizes under `-o` (VERY_OPTIMIZED enables the loop and SLP
  vectorizers; check with `-output_ir`, which writes `.ll` files into `.build/`), or x64 `#asm` with feature blocks.
- `#asm` (how_to/900, x86-64 only): registers are named and allocated by the compiler (`mov result:, 10;`),
  register classes `gpr`, `vec`, `omr`, `str`; pinning `x === a`; sizes on the mnemonic (`mov.32`, `popcnt?T`);
  memory operands `[base + index*scale + disp]`; per-block features `#asm AVX2 { }`; `#asm,no_barrier` (0.2.031) drops
  the memory clobber the LLVM backend adds by default. A procedure-level `#expand` macro can take registers
  (`__reg`). It runs at compile time too, but only in the x64 compiler (how_to/900 does not build on the arm64 Mac:
  "Compile time execution of #asm is not supported if you are running the ARM version of the compiler.").
- arm64: an unguarded `#asm` is an error ("The target of this workspace does not support x64 asm."); guard with
  `#if CPU == .X64` (examples 31, 32). **Address-taken operands are silently ignored on every platform**: if the
  variable is also passed to `print` (or `*x` is taken), the compiler prints only "Info: This variable cannot be used
  as a register operand, because its address gets taken..." and the instruction has no effect (x64 debug, -o and
  -x64 printed 10 instead of 15). Copy into a fresh variable before printing (example 33).
- `Machine_X64` (x64 only): `get_cpu_info() -> Cpu_X86` (vendor, feature leaves), `check_feature(leaves, .AVX2)`,
  `enable_feature/disable_feature` on `build_options.machine_options` via `get_machine_options_x86(*o)`, `prefetch(p,
  .T0)`, `rdtsc`, `rdtscp`, `rdrand`, `rdseed`, `mfence/lfence/sfence`, `pause`. Measured: 285K AVX2 true, AVX512F false.
- `Bit_Operations`: `popcount`, `bit_scan_forward` / `bit_scan_reverse` (1-based index, 0 for input 0), `byte_swap`,
  `byte_swap_in_place`: x64 asm, simple loops on other CPUs (slow there: `@Speed` fallbacks).

## Timing

- `current_time_monotonic() -> Apollo_Time` (clock_gettime MONOTONIC_RAW on Unix); subtract two and convert:
  `to_nanoseconds`, `to_microseconds`, `to_milliseconds` (each returns `(value, success)`), `to_float64_seconds`.
  `current_time_consensus()` is wall-clock time; `to_calendar(t)` → `Calendar_Time` (year, month, ...).
- `seconds_since_init() -> float64` counts from its **first call** (it initializes lazily), not from program start.
- `System.read_cpu_counter() -> u64` (0.2.019): `rdtsc` on x64 (≈3.7 GHz ticks on the 285K: 74M ticks in 20 ms);
  on arm64 Unix it returns only the **nanoseconds field** of `clock_gettime(MONOTONIC_RAW)`, so it jumps back to ~0 every
  second (measured: went backwards once in 1.5 s). Use it only on x64, or not at all.
- Benchmark checklist: one quiet machine; same build flags for A and B (use `-o` unless you study debug cost);
  warm-up run; ≥ 7 runs; report the median and spread (min/max or IQR); keep results live (sum into a checksum and print
  it); compare medians across repeated sessions before claiming a difference (see experiment-design and stats-inference
  for the statistics). Example 34 is a small harness; timings go to stderr so the example output stays stable.

## Allocation costs worth knowing

- `[..]` growth doubles (min 8): reserve when the size is known (`array_reserve`); example 34 counts 1 allocation with
  a reserve vs 8 without for 1000 adds.
- Bump allocators (temp, Flat_Pool, Pool, arenas) waste the old buffers of growing arrays (RESIZE copies).
- Allocator choice for multithreaded allocation-heavy code: the x64 default allocator has no thread caches (the module
  comment estimates ~25% slower than full rpmalloc under threads); `modules/rpmalloc` has them. On macOS arm64 the
  default is the system malloc (see c-perf for macOS malloc scaling numbers). Per-thread arenas avoid the question.
