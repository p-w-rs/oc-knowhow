# Allocators (deep dive)

Verified on Jai beta 0.2.032 (macOS arm64, Linux x86-64). Examples: `examples/jai/jai-systems/08`–`17`.
Sources: `how_to/200_memory_management.jai` (the philosophy: lifetimes and bulk freeing), `how_to/800_allocators.jai`
(the mode protocol), `modules/Preload.jai` (types), `modules/Basic/module.jai` + `Basic/Array.jai` (alloc, New,
array growth), `modules/Default_Allocator/`, `Pool.jai`, `Flat_Pool.jai`, `rpmalloc/`, `Bucket_Array.jai`,
`Overwriting_Allocator/`, `Unmapping_Allocator/`, `Basic/Memory_Debugger.jai`. Library:
`library_search query="Allocator_Mode CAPS IS_THIS_YOURS" sources=["jai-modules-src","jai-how-to"]`.

## The protocol

```jai
Allocator_Proc :: #type (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void;
Allocator      :: struct { proc: Allocator_Proc; data: *void; }
```

`allocator_data` selects the heap/arena instance (null = the allocator's default heap, if it has one). Which
arguments matter per mode, in short (how_to/800 is the specification):

| Mode | Inputs | Returns | Notes |
|---|---|---|---|
| `ALLOCATE` | size | memory or **null = out of memory** | no error codes in Jai allocators |
| `RESIZE` | size, old_size, old_memory | new memory (maybe the same) with the old bytes copied | the caller passes `old_size`, so simple allocators keep no headers |
| `FREE` | old_memory | null | the allocator must know the size itself; bump allocators ignore it |
| `STARTUP` / `SHUTDOWN` | — | null | init once / free everything; the runtime never calls SHUTDOWN on the global heap |
| `THREAD_START` / `THREAD_STOP` | — | null | in 0.2.032 only the **Windows** thread entry sends these; temp, Pool, Flat_Pool assert on them (so pushing those as `context.allocator` around `thread_init` on Windows would assert; untested, no Windows machine) |
| `CREATE_HEAP` / `DESTROY_HEAP` | data = heap to destroy | new heap's data / null | `create_heap(a) -> Allocator`, `destroy_heap(h)` in Basic |
| `IS_THIS_YOURS` | old_memory | non-null if the live block belongs to this heap | memory debugger and tests use it |
| `CAPS` | old_memory = `*string` or null | `Allocator_Caps` cast to `*void` | write an identifying name into the string when non-null |

`Allocator_Caps`: `MULTIPLE_THREADS, CREATE_HEAP, FREE, ACTUALLY_RESIZE, IS_THIS_YOURS`, plus hints
`HINT_I_AM_A_FAST_BUMP_ALLOCATOR, HINT_I_AM_A_GENERAL_HEAP_ALLOCATOR, HINT_I_AM_PER_FRAME_TEMPORARY_STORAGE,
HINT_I_AM_A_DEBUG_ALLOCATOR`. Use `get_capabilities(a) -> (caps, name)` to assert you were handed a suitable
allocator (e.g. `MULTIPLE_THREADS` before sharing it). Pitfall: `get_capabilities` calls the proc with
`allocator_data = null`; allocators that need their data (Overwriting_Allocator, Unmapping_Allocator, the arena below
if it dereferenced data for CAPS) assert or crash. Query those with `a.proc(.CAPS, 0, 0, *name, a.data)`.

Answers measured on 0.2.032:

| Allocator | CAPS name | caps |
|---|---|---|
| default, macOS arm64 | "Jai wrapper for C’s malloc/free/realloc functions." (typographic apostrophe; match on `contains(name, "malloc")`) | MULTIPLE_THREADS, FREE, ACTUALLY_RESIZE, GENERAL_HEAP |
| default, Linux x86-64 | "stripped-down rpmalloc 1.4.4 intended as Default_Allocator" | + CREATE_HEAP, IS_THIS_YOURS |
| `temp` | "modules/Basic temporary_allocator_proc" | PER_FRAME_TEMPORARY_STORAGE |
| rpmalloc module | "rpmalloc 1.4.4" | MULTIPLE_THREADS, CREATE_HEAP, FREE, ACTUALLY_RESIZE, GENERAL_HEAP |
| Pool / Flat_Pool | "modules/Pool" / "modules/Flat_Pool" | FAST_BUMP, IS_THIS_YOURS |
| Overwriting_Allocator | "modules/Overwriting_Allocator" | GENERAL_HEAP, DEBUG, MULTIPLE_THREADS, FREE |

The default allocator is chosen by `Default_Allocator`: on x64 (and Switch 2) a trimmed rpmalloc without thread
caches; on every other CPU (arm64 Macs, Linux arm64) a thin wrapper over C `malloc`/`realloc`/`free` that supports
neither heaps nor IS_THIS_YOURS (it asserts on them). Code relying on `create_heap(context.default_allocator)` is
therefore not portable: use the rpmalloc module for heaps.

## Basic's API (everything goes through context.allocator)

- `alloc(size)`, `free(p)`, `free(s: string)`, `realloc(p, new_size, old_size)`, `alloc_string(n)`,
  `copy_string(s)`, `sprint(...)`, `to_c_string(s)`, `New(T, initialize = true)`,
  `NewArray(count, T, initialize = true, alignment = -1) -> (result: [] T, unaligned_base: *void)`
  (with an alignment it over-allocates and aligns `result.data`: free `unaligned_base`; returns `([], null)` when the
  allocation fails, since 0.2.030), `Initialize(*x)` (run T's initializer in place), `create_heap`, `destroy_heap`,
  `get_capabilities`, `push_allocator`, `remember_allocators(*thing)`.
- Choose the allocator for one call with `,,`: `New(Node,, a)`, `copy_string(s,, temp)`, `free(p,, a)`.
- `New` runs the struct's initializer (field defaults) or zeroes; `initialize = false` leaves the memory as the
  allocator returned it (example 16 shows 0xcd from the Overwriting_Allocator).
- Arrays: `array_reserve(*a, n)`, `array_resize(*a, n, initialize = true)`, `array_free(a)` (frees `a.data` with
  `a.allocator`), `array_reset(*a)` (frees and zeroes the header), `array_reset_keeping_memory(*a)` (count = 0).
  Growth on `array_add` is to max(8, 2 × count) elements via RESIZE.

## Who remembers which allocator

- `[..] T` is 40 bytes: `count, data, allocated, allocator` (the struct is `Resizable_Array` in Preload). The first
  time it needs memory it copies `context.allocator` into `allocator` (Basic's `remember_allocators`), and every later
  growth and `array_free` uses that, wherever the context points then. Measured (example 08): 2 allocations inside a
  `push_allocator` scope, 6 after more `array_add` calls outside it, all counted by the pushed allocator.
- To pick the allocator up front: `arr.allocator = temp;` before the first add (how_to/012 style), or reserve under
  `push_allocator`.
- `string` and `[] T` are 16 bytes (count, data): no allocator. Free them with the allocator that made them:
  `free(s,, a)`. Mixing is undefined behaviour unless the memory debugger catches it.
- Hash_Table, Thread_Group and Xar call `remember_allocators`; String_Builder and Pool copy `context.allocator` on
  first use themselves. **Bucket_Array does not remember**: its `allocator` field is only read; left unset, each new
  bucket comes from `context.allocator` at the time of the add and `bucket_array_reset` frees them with the one
  current at the reset (probe: buckets made under A and B, reset under C: C got both frees). Set `ba.allocator` first.

## The shipped allocators

| | When | API essentials (0.2.032) |
|---|---|---|
| default heap | general, thread-safe | `context.default_allocator`; per-platform implementation (above) |
| `temp` | scratch until a reset | reference/temporary-storage.md |
| `Flat_Pool` | one lifetime, single thread | reserves `DEFAULT_VIRTUAL_MEMORY_RESERVE` (module parameter, 256 MiB) of address space on first use and commits as it grows (on Linux/macOS it simply maps the whole range); `get(*p, n)`, `reset(*p, overwrite_memory = false)` (0xcc stamp), `fini(*p)`; `alignment` field (default 8); allocator proc `flat_pool_allocator_proc` with data `*pool`; FREE ignored; exceeding the reserve asserts |
| `Pool` | older arena | 64 KiB `memblock_size`; allocations ≥ `oversized_size` (6554) get their own block; `set_allocators(*pool)` before pushing it (else it would ask itself for blocks and asserts), `get`, `reset` (keeps blocks), `release`; `overwrite_memory` stamps 0xcc; program parameter `USE_UNMAPPING_ALLOCATOR` puts its blocks on Unmapping_Allocator |
| `rpmalloc` | fast threaded heap with first-class heaps | `rpmalloc_allocator_proc(.STARTUP, 0, 0, null, null)`, then `Allocator.{rpmalloc_allocator_proc, null}`; `create_heap`, then `heap_free_all(xx h.data)` + `destroy_heap(h)` (Heaps below); module parameters `ENABLE_STATISTICS`, `ENABLE_ASSERTS`, `ENABLE_VALIDATE_ARGS` (all true by default: set false for release), `ENABLE_THREAD_CACHE`, `LINUX_HUGE_PAGES`, `USE_RAW` |
| `Bucket_Array(T, N)` | stable addresses, slot reuse | `bucket_array_add(*b, item) -> (locator, *item)`, `bucket_array_find(_pointer)`, `bucket_array_remove(*b, locator)`, `for` with `remove`, `bucket_array_reset`; buckets come from its `allocator` field if set, else from `context.allocator` at each add (it does not remember); no generations: a stale locator silently finds the new occupant (example 43) |

Pool vs Flat_Pool: Flat_Pool is simpler, needs no backing allocator and has flatter performance (no block cycling);
Pool's own header recommends Flat_Pool for new code. Both are single-threaded and invisible to the memory debugger.

## A complete arena (tested: example 09)

```jai
Arena :: struct {
    memory: [] u8;
    used: int;
    last: *u8;            // start of the most recent block, for in-place RESIZE
    allocations: int;
}

ARENA_ALIGNMENT :: 16;

arena_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    arena := cast(*Arena) allocator_data;
    if mode == {
      case .ALLOCATE;
        return arena_push(arena, size);

      case .RESIZE;
        if old_memory && old_memory == arena.last {
            // The last block can simply be extended (or shrunk) if it still fits.
            start := cast(*u8) old_memory - arena.memory.data;
            if start + size <= arena.memory.count {
                arena.used = start + size;
                return old_memory;
            }
            return null;
        }
        result := arena_push(arena, size);
        if result && old_memory  memcpy(result, old_memory, min(old_size, size));
        return result;

      case .FREE;
        return null;      // individual frees are no-ops; call arena_reset()

      case .IS_THIS_YOURS;
        p := cast(*u8) old_memory;
        mine := p >= arena.memory.data && p < arena.memory.data + arena.memory.count;
        return cast(*void) cast(s64) mine;

      case .CAPS;
        if old_memory { (cast(*string) old_memory).* = "example fixed-buffer arena"; }
        return cast(*void) (Allocator_Caps.HINT_I_AM_A_FAST_BUMP_ALLOCATOR | .IS_THIS_YOURS | .ACTUALLY_RESIZE);

      case .STARTUP; #through;
      case .SHUTDOWN;
        return null;

      case;   // THREAD_START, THREAD_STOP, CREATE_HEAP, DESTROY_HEAP
        assert(false, "arena: mode % is not supported", mode);
        return null;
    }
}

arena_push :: (arena: *Arena, size: s64) -> *void {
    // Align the ADDRESS, not the offset: the backing buffer itself may be only 8-byte aligned.
    address := cast(u64) (arena.memory.data + arena.used);
    aligned := (address + (ARENA_ALIGNMENT - 1)) & ~cast(u64) (ARENA_ALIGNMENT - 1);
    start := arena.used + cast(s64) (aligned - address);
    if start + size > arena.memory.count return null;
    arena.used = start + size;
    arena.last = arena.memory.data + start;
    arena.allocations += 1;
    return arena.last;
}

arena_reset :: (arena: *Arena) { arena.used = 0; arena.last = null; arena.allocations = 0; }

arena_allocator :: (arena: *Arena) -> Allocator { return .{arena_allocator_proc, arena}; }
```

Use: `backing: [65536] u8 #align 16; arena := Arena.{memory = backing}; { push_allocator(arena_allocator(*arena));
build_tree(); } ... arena_reset(*arena);`. Measured: 1000 BST nodes of 32 bytes used 31992 bytes; RESIZE of the last
block stayed in place; out of memory returned null; IS_THIS_YOURS was true for a node and false for a heap block.

Lessons from writing it:
- My first version aligned the offset; on a stack buffer that is only 8-byte aligned the results were misaligned.
  Align the address (or align the buffer with `#align 16`; both here).
- `if old_memory (cast(*string) old_memory).* = "...";` does not parse as intended (the parentheses join the
  condition: "Expected a statement before this semicolon"). Use braces.
- A `[..]` growing inside any bump allocator abandons each old buffer (RESIZE = new block + copy unless it is the
  last block). Example 12: 500 strings cost 20256 bytes instead of ~4000. Reserve first.
- Thread safety: none. Use one arena per thread, or add a Mutex and report `MULTIPLE_THREADS`.

## A wrapper (example 08)

The smallest useful allocator forwards to a backing allocator stored in its data and adds behaviour: counting,
logging, budget limits, tracing. Keep CAPS answering with your own name; forward the rest unchanged
(`return c.backing.proc(mode, size, old_size, old_memory, c.backing.data);`).

## Heaps

`h := create_heap(a)` returns an `Allocator` with the same proc and new data; allocate with `New(T,, h)` or
`push_allocator(h)`. Supported by the rpmalloc module and the x64 default allocator, not by the arm64 default
allocator (CREATE_HEAP asserts there).

**`destroy_heap(h)` does not free the heap's blocks (0.2.032).** Both implementations answer DESTROY_HEAP by parking
the heap on an orphan list (rpmalloc's `heap_release` semantics), and the next `create_heap` returns that same heap
with every old block still allocated. Measured: 30 rounds of create, 100000 × 96 bytes, destroy: maxrss 12 → 278 MB
(Mac with the rpmalloc module; powerslabs with the module and with the default allocator); with `heap_free_all`
first it stayed at 12–15 MB. The memory debugger's destroy_heap hook marks the heap's blocks freed, so
`report_memory_leaks()` shows nothing. Free first, then destroy (examples 13 and 42):

```jai
heap_free_all(xx h.data);           // rpmalloc module: frees every block (its Heap type is not exported: xx)
destroy_heap(h);                     // then park it for reuse
```

## Choosing by lifetime and size

how_to/200 sorts dynamic memory by lifetime: (1) gone by the end of the function, (2) gone at a clear later point,
(3) long-lived but owned by one subsystem, (4) long-lived with unclear ownership (rare: a hint to redesign). A second
question, whether the size is known, picks the tool. The full guide (costs, pitfalls, how each allocator makes data
structures fast or slow, writing a pool or a heap) is reference/memory-strategies.md, with examples 41–45:

| | size known | size unknown |
|---|---|---|
| lifetime known | `[N] T`, one exact block, carved columns; free once or never (41) | arena reset at the end: `temp`, `Flat_Pool`, chunk arena (42) |
| lifetime unknown | slot pool + free list + generational handles (43) | default heap / rpmalloc with `free` (44) |

- Data owned by value inside its owner (no separate allocation) beats all of the above.
- Library code that allocates and never frees is fine inside a pushed arena.
- Stable pointers to many same-type items: an arena, a slot pool, or Bucket_Array (no generations: a stale locator
  finds the new occupant).
- A heap per lifetime needs `heap_free_all` before `destroy_heap` (above).

## Debugging allocators

### The memory debugger (Basic program parameters)

- `#import "Basic"()(MEMORY_DEBUGGER=true);` in one place (program parameters apply to every import of Basic;
  supplying them twice is an error: "Cannot supply program parameters for the same module twice."). It hooks
  `alloc`, `free`, `realloc`, `create_heap`, `destroy_heap` in Basic, records each allocation with a packed stack trace
  and the thread index, and checks frees. Allocations made by calling an allocator proc directly bypass it; temp,
  Pool and Flat_Pool allocations are deliberately skipped. It slows allocation-heavy programs down; enable it for
  memory work, not always.
- `report_memory_leaks(options = .{})` prints (stdout) groups by allocation call stack, e.g.
  `----- 480 bytes in 3 allocations -----` followed by `NewArray .../Basic/module.jai:395`, `make_list file:6`,
  `main file:18`, then `Total: 485 bytes in 4 allocations.` and `Marked as non-leaks: 8 bytes in 1 allocation.`
  `Leak_Report_Options`: `known_allocation_leaves` and `roots_to_skip` (`Procedure_To_Elide` name/module pairs that
  trim the printed stacks), `group_by_these_calls`, `scan_global_memory_to_remove_leaks = true` (blocks reachable from
  globals are not leaks), `scan_leaks_to_combine = true` (blocks reachable from a leak are folded into it).
  `make_leak_report` / `log_leak_report` / `deinit(*report)` give you the data instead of printing.
- Marking: `this_allocation_is_not_a_leak(p)` (intentional global data; an empty macro when the debugger is off),
  `this_allocation_leaks_todo(p)` (same effect, documents intent), `this_allocation_does_not_propagate_leak_ownership(p)`
  (the debug allocators use it on their own tables), `allocations_before_this_call_will_not_be_considered_leaks()`.
- Errors it reports (all with call stacks and thread indices): free of memory already freed (three stacks: this free,
  the earlier free, the allocation), free of an address Basic never allocated ("not generated by Basic.alloc": the
  program exits 1), free with a different allocator than the allocation (verified: "When calling Basic.free(), there
  was an allocator/allocator_data mismatch" with both allocators named and both stacks; the wrong allocator then
  crashed the program), and, from the source, allocation of an address that is still live.
  By default it logs and continues (then the underlying allocator decides: macOS malloc traps on a double free, the x64
  default allocator carried on); `MEMORY_DEBUGGER_REPORT_ASSERTS=true` (since 0.2.031) asserts after each report
  (example 15).
- `VISUALIZE_MEMORY_DEBUGGER` (default true when the debugger is on): the program streams allocation data over a
  Shared_Memory_Channel to the bundle's `examples/codex_view` GUI if it is running; call
  `memory_visualizer_per_frame_update()` once per frame (an empty macro otherwise). The wire format is
  `modules/Protocol_For_Memory_Visualization.jai`. Not exercised here (GUI).
- `REPLACEMENT_INTERFACE`: plug in your own checker with `check_alloc`, `check_free`, `check_create_heap`,
  `check_destroy_heap`.

### Overwriting_Allocator

`get_overwriting_allocator(base = context.allocator, overwrite_byte = 0xcd)` wraps any allocator: fresh memory is
filled with the byte (unless the caller initializes it, as `New` does), freed memory is overwritten before it goes back
to the base allocator, RESIZE always moves, and a size table (Hash_Table + Mutex) detects double frees and frees of
foreign pointers ("Pointer ..., being freed by overwriting_allocator_proc, was previously freed! ..." then an assert).
Cheap enough for everyday debug builds. The base allocator may still reuse freed blocks: macOS malloc zeroes them, the
x64 default allocator kept the stamp except the first 8 bytes. Over a Flat_Pool (example 16) the stamp stays intact.
`deinit_overwriting_allocator(a)` releases it.

### Unmapping_Allocator

`get_unmapping_allocator()`: every allocation gets fresh pages, positioned so the block ends at a page boundary
followed by an inaccessible page; FREE makes the pages inaccessible and never reuses them. Overruns past the end and
use-after-free fault at the faulting instruction (examples 17 and a Pool built with `USE_UNMAPPING_ALLOCATOR=true`:
reading a pool block after `reset` crashed). Reads before the start are not caught. The crash handler's text is
misleading for these faults (Linux: "SEGV_ACCERR ... write to read-only memory" even for reads; macOS: "SIGBUS ...
invalid address alignment"). Slow and the page table keeps growing: debug builds only.
