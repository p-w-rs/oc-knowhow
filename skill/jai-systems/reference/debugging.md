# Debugging Jai programs (deep dive)

Verified on Jai beta 0.2.032: lldb 2103 (Xcode) on macOS arm64, GNU gdb 18.1 on Linux x86-64 (powerslabs).
Examples: `examples/jai/jai-systems/15`, `17`, `35`–`39`. Sources: `modules/Runtime_Support.jai` (check failures,
`debug_break`), `modules/Runtime_Support_Crash_Handler.jai`, `modules/Basic/module.jai` (`assert`, stack traces),
`modules/Debug/`, `how_to/700_stack_trace.jai`, `editor_support/msvc/`. Program used below (scratch `dbg/dbg.jai`):

```jai
Vec3 :: struct { x, y, z: float; }
Particle :: struct { name: string; pos: Vec3; tags: [..] string; mass: float64; }

total_mass :: (ps: [] Particle) -> float64 {     // line 12
    sum: float64 = 0;
    for ps {
        sum += it.mass;   // line 15
    }
    return sum;
}
// main (line 20) fills ps: [..] Particle with 3 particles "p0".."p2" (tags ["hot"], mass 1.5, 3, 4.5),
// then fixed: [4] int, view: [] int = fixed, greeting := "hello, debugger", m := total_mass(ps) (line 33), print (34).
```

## Debug information

- Default builds (`jai f.jai`) carry full debug info: macOS runs `dsymutil` and writes `prog.dSYM` next to the
  executable; Linux puts DWARF into the ELF. `-od` and `-o` keep line tables too (`set_optimization` defaults to
  `preserve_debug_info = true`) but variables get optimized out. Linux executables are linked non-PIE ("ELF 64-bit LSB
  executable"), so addresses in crash reports are the addresses in the file.
- `Build_Options.emit_debug_info`: `NONE`, `DWARF`, `CODEVIEW`, `DEFAULT`. `-natvis` (`use_natvis_compatible_types`)
  renames types in the debug info to C++-like names (`array_view<Particle>` instead of `[] Particle`, checked in lldb)
  so Visual Studio's natvis file matches.
- lldb marks every Jai frame `[opt]` and warns "compiled with optimization - stepping may behave oddly" even for
  debug builds; in debug builds all locals were visible anyway.
- Symbol names: procedures carry a hex suffix in the symbol table (`total_mass_b000000a7`), `main` is
  `__program_main`, the C `main` is `__system_entry_point_*` (Runtime_Support.jai:446). The DWARF names are the plain
  Jai names, which gdb shows (`total_mass`, `main`). Every procedure frame has a `context` parameter first.

## lldb (macOS), a real session

`lldb --batch -o "<cmd>" ... ./dbg` runs commands in order (handy for agents; interactive use is the same commands).
Output trimmed only where marked.

```
(lldb) breakpoint set --file dbg.jai --line 15
Breakpoint 1: where = dbg`total_mass_b000000a7 + 116 at dbg.jai:15, address = 0x0000000100011750
(lldb) run
* thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 1.1
       frame #0: 0x0000000100011750 dbg`total_mass_b000000a7(context=0x0000000100031000, ps=0x000000016fdfe550) at dbg.jai:15 [opt]
-> 15  	        sum += it.mass;   // line 15
(lldb) frame variable ps sum it it_index
([] Particle &) ps = 0x000000016fdfe550: {
  count = 3
  data = 0x00000001005d5e50
}
(float64) sum = 0
(Particle &) it = 0x00000001005d5e50: {
  name = (count = 2, data = "p0")
  pos = (x = 0, y = 2, z = 3)
  tags = {
    count = 1
    allocated = 8
    data = 0x00000001005d5c20
    allocator = 0x0000000100015668
    allocator_data = 0x0000000000000000
  }
  mass = 1.5
}
(s64) it_index = 0
(lldb) p it.name
(string)  (count = 2, data = "p0")
(lldb) p *ps.data[1].tags.data
(string)  (count = 3, data = "hot")
(lldb) parray 2 ps.data
(Particle *) $0 = 0x00000001005d5e50 {
  [0] = { name = (count = 2, data = "p0") ... mass = 1.5 }        <- trimmed
  [1] = { name = (count = 2, data = "p1") ... mass = 3 }
}
(lldb) breakpoint disable 1
(lldb) finish
Return value: (float64) $1 = 9
-> 33  	    m := total_mass(ps);
(lldb) next
-> 34  	    print("% % % %\n", m, greeting, view.count, fixed[1]);
(lldb) frame variable greeting fixed view m
(string) greeting = (count = 15, data = "hello, debugger")
(s64[4]) fixed = ([0] = 10, [1] = 20, [2] = 30, [3] = 40)
([] s64) view = {
  count = 4
  data = 0x000000016fdfe478
}
(float64) m = 9
(lldb) memory read -s1 -c15 -fc greeting.data
0x10001f977: hello, debugger
```

- Breakpoints: `breakpoint set --file f.jai --line N` (`b f.jai:N`), `breakpoint set --name total_mass` (the plain
  name works; it stops after the prologue, line 13), `--func-regex '^total_mass_'`, `--name __program_main` for main.
  `bt` showed `total_mass_b000000a7 ... dbg.jai:13`, `__program_main ... dbg.jai:33`,
  `__system_entry_point_700000397 ... Runtime_Support.jai:446`, `dyld start`.
- Values: strings print as `(count = N, data = "...")`, `[] T` as `{count, data}` (then `parray count view.data`),
  `[..] T` as `{count, allocated, data, allocator, allocator_data}`, fixed arrays element by element, structs by
  member. Globals (`p counter`) and arithmetic (`p n * 10`) work. Calling Jai procedures from lldb was not tried (they
  need the hidden context argument).
- **Strings and views are shown as C strings**: lldb prints `data` up to a NUL byte, ignoring `count`. A 5-byte slice
  of "hello, debugger" displayed as `(count = 5, data = "hello, debugger")`. Read exactly `count` bytes with
  `memory read -s1 -fc -c<count> s.data` (gave `hello`).
- A local shown before its assignment line holds garbage (`m = 9.4153164841824822E-314` when stopped at line 33).
- `-natvis` builds show `(array_view<Particle> &) ps`; nothing else changes for lldb.
- Batch-mode gotchas: the first failing `-o` command stops the rest (asking for `it`/`it_index` at line 13, outside
  the loop's scope: "use of undeclared identifier 'it_index'", and nothing after it ran). After an exception stop
  (crash, `debug_break`), `-o` commands no longer run: pass them with `-k` ("on crash").

`debug_break()` under lldb (scratch `dbg/brk.jai`, the break is inside `step`):

```
$ lldb --batch -o run -k "bt 3" -k up -k "frame variable n" -k "p counter" -k "p n * 10" -k kill ./brk
* thread #1, queue = 'com.apple.main-thread', stop reason = EXC_BREAKPOINT (code=1, subcode=0x1000058ac)
       frame #0: 0x00000001000058b0 brk`debug_break_11000003e5 at Runtime_Support.jai:474 [opt]
(lldb) bt 3
   * frame #0: ... brk`debug_break_11000003e5 at Runtime_Support.jai:474 [opt]
     frame #1: ... brk`step_3000000d4(context=0x0000000100031000, n=3) at brk.jai:5 [opt]
     frame #2: ... brk`__program_main(context=0x0000000100031000) at brk.jai:9 [opt]
(lldb) up
-> 5   	    if counter > 5 debug_break();
(lldb) frame variable n
(s64) n = 3
(lldb) p counter
(s64) 6
(lldb) p n * 10
(s64) 30
```

`debug_break` is a procedure in Runtime_Support (an `int3` on x64, a `BRK` instruction emitted with `#bytes` on arm64),
so the stop is one frame below your code: `up` once. Without a debugger it ends the program through the crash
handler ("Breakpoint hit. Stack trace:", exit 1).

## gdb (Linux), a real session

```
$ gdb -q -batch -ex "break dbg.jai:15" -ex run -ex bt -ex "info locals" -ex "print it.name" \
      -ex "print *it.name.data@it.name.count" -ex "print ps.count" -ex "print *ps.data[1].tags.data" -ex delete \
      -ex finish -ex next -ex "print m" -ex "print greeting" -ex "x/15c greeting.data" -ex "print fixed" \
      -ex "print *view.data@view.count" -ex "info functions total_mass" -ex kill ./dbg
Breakpoint 1 at 0x22a2c9: file /home/you/dbg/dbg.jai, line 15.
Breakpoint 1, total_mass (context=..., ps=...) at /home/you/dbg/dbg.jai:15
15	        sum += it.mass;   // line 15
#0  total_mass (context=..., ps=...) at .../dbg.jai:15
#1  0x0000000000235d85 in main (context=...) at .../dbg.jai:33
#2  0x000000000021c8ea in __system_entry_point (argc=1, argv=0x7fffffffebf8) at .../modules/Runtime_Support.jai:446
it = @0x7ffff7810080: {name = {count = 2, data = 0x247240 <_bss_base+576> "p0"}, pos = {x = 0, y = 2, z = 3}, tags = {count = 1, allocated = 8, data = 0x7ffff7800080, allocator = 0x23d9c0 <allocator_proc>, allocator_data = 0x0}, mass = 1.5}
it_index = 0
sum = 0
$1 = {count = 2, data = 0x247240 <_bss_base+576> "p0"}
$2 = "p0"
$3 = 3
$5 = {count = 3, data = 0x20b795 <__literal_11925> "hot"}
Run till exit from #0 ...
Value returned is $6 = 9
34	    print("% % % %\n", m, greeting, view.count, fixed[1]);
$7 = 9
$8 = {count = 15, data = 0x20b799 <__literal_11929> "hello, debugger"}
0x20b799 <__literal_11929>:	104 'h'	101 'e'	108 'l'	108 'l'	111 'o'	44 ','	32 ' '	100 'd'
0x20b7a1 <__literal_11929+8>:	101 'e'	98 'b'	117 'u'	103 'g'	103 'g'	101 'e'	114 'r'
$9 = {10, 20, 30, 40}
$10 = {10, 20, 30, 40}
File .../dbg.jai:
12:	float64 total_mass(Context1 &, [] Particle &);
```

- `break total_mass` and `break dbg.jai:15` both work; gdb shows `main` for `__program_main`.
- Strings: `print s` shows `{count, data}` and reads `data` as a C string (a 5-byte slice of "hello, debugger"
  printed `"hello, debugger"` again); `print *s.data@s.count` gives exactly the string (`"hello"`). Views:
  `print *view.data@view.count`.
- `-x64` backend builds: breakpoints and locals work, but `[..]` members appear in a different order
  (`count, data, allocated, ...`) and gdb printed warnings like "pc 0x25f240 in address map, but not in symtab" around
  string data.
- `-o` builds: `break dbg.jai:15` resolved to 2 locations (the loop was transformed) and `it`, `it_index` were
  `<optimized out>`; `sum` was still visible.
- No Jai pretty printers ship for gdb or lldb. A community set exists (`jai-on-linux-source`, valignatev, MIT,
  `gdb_helpers/`): not tried here. The built-in output above is usable for structs, slices and fixed arrays.
- Visual Studio (Windows, not tested here): `editor_support/msvc/jai.natvis` (views `array_view<*>`, resizable
  arrays, strings, Type_Info, Math vectors and matrices) and `jai.natstepfilter`; build with `-natvis`.

## When the program dies: what is printed

Runtime checks (debug builds) print to stderr, then "Panic.", then `debug_break` (which, without a debugger, goes to
the crash handler: "Breakpoint hit. Stack trace:" plus native frames) and exit code 1.

| Failure | First lines (exact, 0.2.032) | Exit |
|---|---|---|
| array index | `Array bounds check failed. (The attempted index is 3, but the highest valid index is 2). Site is <file>:11.` / `Panic.` | 1 |
| empty `[..]` index | `Array bounds check failed. (The attempted index is 5, but the array has dimension 0, so no index is valid). Site is ...` | 1 |
| narrowing cast | `Cast bounds check failed.  Number must be in [0, 255]; it was 302.  Site is <file>:26.` / `Panic.` | 1 |
| `*T` passed to a `T` parameter, null | `Null pointer check failed: Argument 1 is undergoing an automatic dereference, but the pointer is null. Site is ...` | 1 |
| overflow (only with `arithmetic_overflow_check`) | `Arithmetic overflow. We tried to compute:` / `    2147483647 + 2` / `The operand type is s32, but the result does not fit into this type.` | 1 |
| `assert` | `<file>:42,9: Assertion failed: v was 2 (expected 1)` / `Stack trace:` / Jai frames `file:line: name` | 1 |
| `p.field` with p null, Linux | `Program Exception: SEGV_MAPERR` / `Null Pointer Exception. Attempt to dereference a null pointer.` / `Segmentation fault. The faulty address is 0x0, from 0x...` + frames | 1 |
| same, macOS | `Program Exception: SEGV_ACCERR` / `The program crashed because it tried to write to read-only memory.` (it was a read) | 1 |
| integer ÷ 0, Linux | `SIGFPE: The program crashed because of an integer division by zero error.` | 1 |
| integer ÷ 0, macOS arm64 | **nothing: the result is 0** (arm64 division does not trap) | 0 |
| guard page (Unmapping_Allocator), Linux / macOS | `SEGV_ACCERR ... write to read-only memory` / `SIGBUS: ... invalid address alignment` | 1 |
| stack overflow | **nothing printed** | 139 Linux, 132 macOS |
| any of these with `-no_backtrace_on_crash` | the check message (if any), then the raw signal | 139 segfault, 133 trap |

- The crash handler (`Runtime_Support_Crash_Handler`, installed at startup unless `backtrace_on_crash = .OFF`)
  catches SIGSEGV, SIGTRAP, SIGFPE, SIGBUS and SIGILL, prints a reason and the native backtrace
  (`backtrace_symbols`), and `_exit(1)`s. Frames look like `./p5_crash(__program_main+0x3b7) [0x215497]` on Linux and
  `3   nullchk   0x0000000100ee1370 __program_main + 392` on macOS.
- Under `-o`/`-od` the bounds, cast and null checks are compiled out: an out-of-range read returned garbage
  (6551043978) and exited 0; asserts stay (with an empty "Stack trace:" under `-o`).
- Turn a native frame into a source line:
  - Linux (non-PIE): `addr2line -f -e p5_crash 0x215497` → `__program_main` /
    `/home/you/probes/p5_crash.jai:19` (the faulting `print` line).
  - macOS (ASLR): find the symbol's static address and add the printed offset:
    `lldb --batch -o "image lookup -s __program_main" ./nullchk` (→ `nullchk[0x000000010000d1e8]`), then
    `lldb --batch -o "image lookup -a 0x10000d370" ./nullchk` (0x...d1e8 + 392) → `__program_main + 392 at nullchk.jai:7`.

## Jai stack traces (no debugger needed)

- With `Build_Options.stack_trace = true` (default; `-o` sets it false) each call pushes a `Stack_Trace_Node` on the
  machine stack: `next`, `info` (`name`, `location`, `procedure_address`), `hash`, `call_depth`, `line_number` (the
  line of the call currently being made from that frame). `context.stack_trace` is the innermost node; the chain ends
  in a sentinel node with `info == null`. Cost: 2–2.7× on call-heavy code (reference/performance.md).
- `print_stack_trace(node, prefix = "", to_standard_error = true)` (never allocates or logs: safe in allocators and
  handlers), `get_stack_trace_strings(node = null) -> [..] string` (temp, `'name' at file:line`; since 0.2.020),
  `log_stack_trace(node, flags)`, `pack_stack_trace(node) -> [] Stack_Trace_Node` (heap copy with fixed-up `next`
  pointers; the no-argument overload also records its own frames). Example 39.
- Calls coming back from C (callbacks) start a new chain: frames before the C code are not visible (how_to/700).
- The memory debugger, assert reports and Iprof use these nodes; native backtraces don't need them.

## assert and handlers

- `assert(condition, format = "", args..)` is a macro (`#expand`, `#no_debug`) in Basic: on failure it calls
  `assert_helper`, which formats with `tprint` and calls `context.assertion_failed(loc, message) -> bool`; true means
  `debug_break()`. The default handler prints the report shown above and returns true. Example 35 installs a collecting
  handler that returns false.
- `#import "Basic"()(ENABLE_ASSERT=false)` replaces assert with an empty macro whose arguments are `#discard`ed: the
  condition is not evaluated. `-o` keeps asserts.
- Handlers must return `bool` (since 0.1.077). **`modules/Debug`'s `no_assert`, `print_assert` and `trace_assert` do
  not**, so `context.assertion_failed = Debug.print_assert;` fails: "Type mismatch: Different numbers of return values
  (1 versus 0)." Only `Debug.break_assert` (and `interactive_assert` with graphics) fit.

## modules/Debug

`Debug :: #import "Debug"(USE_GRAPHICS = false);` (graphics pulls X11 on Linux for a message box).
- `init()`: installs a signal handler (since 0.2.031 it logs like the crash handler, through the logger) and, if the
  current assert handler is the default one, replaces it: with `USE_GRAPHICS=false` by `break_assert`, which prints
  `<file>:5,5 Assert Failed: boom` and **continues** when no debugger is attached (exit 0 in our run); with
  `USE_GRAPHICS=true` by `interactive_assert`, which on macOS printed the message and a call stack and exited with code 3
  (`abort(.Assert)`; no dialog is implemented for macOS). Know which you get before calling `init()`.
- `backtrace() -> [] string` (allocates; native frames like `0   q   0x... inner_110000013d + 168`),
  `backtrace(trace: [] *void, skip)` (no allocation), `free_backtrace`, `is_debugger_present()` (macOS: sysctl
  P_TRACED; Linux: TracerPid in /proc/self/status), `breakpoint()` (debug_break only when a debugger is present, so it
  is safe in shipped builds), `break_once()`, `attach_to_debugger()` (false on Unix), `abort(exit_code)`.
  The module itself says most features are Windows-first.

## Compile-time debugging

- A crash inside `#run` (scratch probe dereferencing null at compile time) prints:

```
Error: Jai encountered an exception running the program and is terminating.
Program Exception: SEGV_ACCERR
The program crashed because it tried to write to read-only memory.
Segmentation fault.The faulty address is 0x0000000000000000, from 0x100f80c30 (file address 0x100030c30).

This crash happened during compile-time execution of Workspace #2, so it may be a bug in the user-level program, not in the compiler.

Here's a stack trace of the user-level program:

                     bad (.../q.jai:2,37)
            body of #run (.../q.jai:3,11)

If you want to interactively debug crashes in compile-time execution, run the compiler with the -debugger command-line option.
```

- An `assert` failing in `#run` prints the normal assertion report (with the `#run` body as `(anonymous procedure)`)
  and then "There were errors on Workspace 2. Exiting."
- `-debugger` (formerly `-debug`, which is now "Unknown argument") drops into the interactive bytecode debugger on a
  compile-time crash; `set_build_options_dc(.{interactive_bytecode_debugger = true})` does it from code. Interactive:
  not exercised here.
- `#dump` after a procedure's signature prints its bytecode when it is compiled:
  `add :: (a: int, b: int) -> int #dump { return a + b; }` printed "Disassembly of 'add' in Workspace 2 at ...",
  "-------- Basic Block 0 --------", `binop v4, v1 + v2`, `return_value v4 -> 1`, `return`.
- `-output_ir` writes the LLVM IR (`.build/<name>_N_wM.ll` and `_no_opt.ll`).

## Memory errors

See reference/allocators.md#debugging-allocators: the memory debugger (leaks, double free, wrong allocator, foreign
pointer), Overwriting_Allocator (0xcd patterns, double free), Unmapping_Allocator (overruns and use-after-free fault at
the access), `TEMP_ALLOCATOR_OVERWRITE_MEMORY` (stale temp pointers). Without any of these a heap overrun plus a
use-after-free ran silently to exit 0 on Linux. There is no sanitizer option in `Build_Options` or on the command
line (0.2.032). Valgrind memcheck could not
be checked: on powerslabs (Arch) it refused to start ("A must-be-redirected function whose name matches the pattern:
memcmp ... was not found", it needs glibc debug info), ubuntu-laptop has no valgrind. Note that on x64 the default
allocator is rpmalloc on top of mmap, so memcheck would at best see Jai heap blocks only if you route allocations to C
malloc. Callgrind (profiling) did work on powerslabs.
