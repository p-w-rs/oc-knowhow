# Memory strategies: the four lifetime × size situations (deep dive)

Verified with Jai beta 0.2.032 on macOS arm64 and Linux x86-64 (27 Nov 2026): every example below passes on the Mac
(M2 Max), **powerslabs** and **ubuntu-laptop**; every probe quoted here ran on the Mac and powerslabs.
Examples: `examples/jai/jai-systems/41`–`45` (this guide), `08`–`13` and `18`–`22` (the allocator API, temp).
Sources read: `how_to/200_memory_management.jai` (lifetimes, bulk freeing), `how_to/800_allocators.jai` (the mode
protocol), `modules/Basic/module.jai` + `Basic/Array.jai` (alloc, New, NewArray, `[..]` growth),
`modules/Flat_Pool.jai`, `modules/Pool.jai`, `modules/Bucket_Array.jai`, `modules/Default_Allocator/module.jai`,
`modules/rpmalloc/`, `Basic/Temporary_Storage_Paged_Alloc.jai`, `Basic/Memory_Debugger.jai`. Library:
`library_search query="Flat_Pool reset fini" sources=["jai-modules-src"]`. Protocol and shipped allocators:
reference/allocators.md. Timings of the effects described here (Mac M2 Max, powerslabs, ubuntu-laptop): reference/caches.md;
the headline numbers are in "How the allocator makes a data structure fast or slow" below.

## Decide with two questions

Before writing `New`, ask about each kind of data: **do I know how long it lives** (until a point I can name: end of
frame, request, file, level, program)? **Do I know how much of it there will be** (an exact count, or one fixed size
per object)? The answers pick the allocator.

| | **size known** | **size unknown** |
|---|---|---|
| **lifetime known** | **(1)** one exact block or `[N] T`; free once or never (ex. 41) | **(2)** arena reset at the end: `Flat_Pool`, `temp`, chunk arena (ex. 42) |
| **lifetime unknown** | **(3)** slot pool + free list + generational handles (ex. 43) | **(4)** general heap: default allocator, rpmalloc (ex. 44) |

| Situation | Allocator choices in Jai | Cost and behaviour | Pitfalls | Ex. |
|---|---|---|---|---|
| 1. known lifetime, known size | `[N] T` local or struct member; `NewArray(n, T)` once; one `alloc` carved into several arrays; `array_reserve(*a, n)` | 0–1 allocator calls, contiguous, no headers, no growth, one `free` (none for data that lives until exit) | sizes that are really upper bounds: reserve the bound and refuse overflow; alignment over 16 bytes needs over-allocation | 41 |
| 2. known lifetime, unknown size | `Flat_Pool` (`reset`, `fini`), `temp` + `reset_temporary_storage()` / `auto_release_temp()`, your own chunk arena, `Pool` (older) | allocation is a pointer bump; FREE ignored; reset is one call whatever the count; addresses stay put until the reset | pointers that outlive the reset; a growing `[..]` inside a bump allocator abandons each old buffer (reserve first); `destroy_heap` does not free rpmalloc heaps (below) | 42 |
| 3. unknown lifetime, known size | your own slot pool with a free list (0.2.032 ships none); `Bucket_Array(T, N)` for stable addresses without generations | O(1) add/remove, freed slots reused LIFO, no size rounding (8 bytes per slot for generation + index), contiguous chunks; handles detect reuse | plain pointers/indices into reused slots silently alias the new occupant; `Bucket_Array` has no generations and scans for free slots | 43 |
| 4. unknown lifetime, unknown size | `context.default_allocator` (x64: size-class rpmalloc; arm64 macOS: C malloc); `rpmalloc` module (thread caches, heaps) | every block rounded up to a size class (rpmalloc and the x64 default: 16 bytes minimum, 1025 becomes 1536), free-list reuse, thread-safe | fragmentation, scattered objects; `free` must use the allocator that allocated; how_to/200 treats long-lived data with unclear ownership as rare and a likely design flaw | 44 |

Example 45 puts all four in one program (a game loop) and checks at the end that every allocator is back to zero.

## Situation 1: known lifetime, known size (example 41)

The cheapest case: decide the size once, allocate once (or not at all), never grow, never copy, free once.

- **Count first, then allocate.** Two passes over the input cost less than regrowth, and the second pass can fill
  arrays of exactly the right length. Example 41 parses 6 rows: 1 heap call for everything; the names stay views into
  the input text (`split_from_left` returns slices, no copies), which is valid because the text outlives the table.
- **One block, several arrays.** Add up the column sizes, round each start up to the alignment you want, allocate
  the total and slice `[]` views out of it (struct-of-arrays in one allocation; one `free` releases all columns):

```jai
offsets[1] = round_up(offsets[0] + rows * size_of(u32),     LINE);
offsets[2] = round_up(offsets[1] + rows * size_of(string),  LINE);
offsets[3] = round_up(offsets[2] + rows * size_of(float32), LINE);
total     := offsets[3] + rows * size_of(bool);
t.block = alloc(total + LINE - 1);                  // the only heap call
base := cast(*u8) round_up(cast(int) t.block, LINE);
t.ids.data = cast(*u32) (base + offsets[0]);        // ...and so on; .count = rows for each column
```

  General heaps hand out 16-byte aligned blocks (measured: every block of 1..200 bytes from the default heap and from
  rpmalloc was 16-byte aligned on both platforms). For 64 bytes, over-allocate by 63 and round the address up, then
  free the pointer the allocator returned. `NewArray(n, T, alignment = 64)` does the same (it over-allocates by the
  alignment) and returns `(array, unaligned_base)`: free `unaligned_base`. `Flat_Pool` has an `alignment` field
  (default 8; 64 verified).
- **Size known at compile time: no allocator.** `[10] int` as a local lives on the stack; as a struct member it
  lives wherever the struct lives (`Histogram` in example 41: 88 bytes, 0 heap calls). 0.2.032 has no `alloca`: a
  runtime-sized stack array does not exist, so a runtime size means `NewArray`, `talloc` or an arena.
- **Upper bounds.** If you know only "at most N", reserve N once (`array_reserve`) and refuse anything past it
  (example 41's `add_bounded` checks `count == allocated`), or fill a bound-sized scratch buffer in `temp` and keep
  an exact-size copy (`array_copy(view,, a)`). Either way: one allocation, never a regrowth.
- What you avoid: a `[..]` that does not know its size regrows to max(8, 2 × count) elements (Basic's
  `maybe_grow`), each step a RESIZE that may copy everything. Example 41: 1000 `array_add`s made 8 allocator calls;
  after `array_reserve(*b, 1000)`, 1.

## Situation 2: known lifetime, unknown size (example 42)

The data grows until a moment you can name, then all of it dies together: one request, one file, one level, one
frame. Use an arena: allocation is a pointer bump, individual frees are ignored, and the end of the lifetime is a
single reset.

- **Shipped arenas.** `Flat_Pool`: reserves address space on first use (`DEFAULT_VIRTUAL_MEMORY_RESERVE`, a module
  parameter, 256 MiB; `init(*pool, reserve)` for another size). Reserving costs no memory: measured maxrss stayed at
  1.5 MB after the reservation and rose to 101.5 MB only after touching 100 MiB of it. `reset(*pool)` moves one
  pointer back and keeps the pages (Flat_Pool.jai never decommits, so the next level reuses resident memory);
  `reset(*pool, overwrite_memory = true)` stamps 0xcc first; `fini` returns the range. Exceeding the reserve
  asserts. `temp`: per thread, reset by `reset_temporary_storage()`, overflow pages when the first page is full
  (reference/temporary-storage.md). `Pool`: older, 64 KiB blocks from a backing allocator; its own header
  recommends Flat_Pool for new code.
- **Push it around code that allocates and never frees.** Library code needs no changes: everything it allocates
  through `context.allocator` lands in the arena.

```jai
flat: Flat_Pool;
{
    push_allocator(flat_pool_allocator_proc, *flat);
    head := build_list(300);              // "library" code: New + sprint, never frees
}
reset(*flat);                             // O(1), however many allocations there were
```

- **Addresses never move.** A bump allocator never relocates a block, so pointers between arena objects stay valid
  until the reset. That is what makes arena-built trees and linked structures safe. Contrast: elements stored *inside*
  a `[..]` move whenever it grows. Example 42 adds 300 entries by value to a `[..]`: the elements moved 6 times, and a
  pointer taken before the growth read a stale copy (0 instead of 1000). The fix keeps both: allocate the objects
  from the arena and keep a growing `[..]` of *pointers* as the index; the index moves, the objects don't.
- **Writing a growing arena** (example 42's `Chunk_Arena`): bump inside fixed-size chunks from a backing allocator;
  when a chunk is full, link a new one (a request larger than a chunk gets its own); `reset` frees all chunks but the
  first, `release` frees them all. Align the *address*, not the offset. RESIZE can grow the most recent block in
  place; anything else copies. Measured: 300 entries (32-byte struct + 5–7-byte name each) took 4 chunks of 4 KiB at
  16-byte alignment (48 bytes per entry; 40 at the 8-byte alignment of Flat_Pool and temp).
- **A heap per lifetime** (`h := create_heap(rpmalloc)`, allocate, `destroy_heap(h)`) is the same idea with a
  general heap behind it, so individual frees work too. **Trap (0.2.032): `destroy_heap` does not free the heap's
  blocks.** In the rpmalloc module and in the x64 default allocator, DESTROY_HEAP only parks the heap on an orphan
  list (the semantics of C rpmalloc's `rpmalloc_heap_release`, documented as not freeing in the C header bundled in
  `modules/rpmalloc/c_source`); the next `create_heap` returns the same heap with the old blocks still allocated.
  Measured: 30 rounds of create, 100000 × 96 bytes, destroy: maxrss 12 → 278 MB (Mac with the rpmalloc module;
  powerslabs with the module and with the default allocator); calling `heap_free_all` first kept it at 12–15 MB.
  Example 42 shows it with IS_THIS_YOURS: after 3 rounds the heap still owned all 3 blocks. The memory debugger does
  not see this leak: its `destroy_heap` hook marks every block of the heap as freed, so `report_memory_leaks()`
  printed `Total: 0 bytes in 0 allocations.` while the heap still owned its block.

```jai
rp :: #import "rpmalloc";
rp.heap_free_all(cast(*rp.Heap) level.data);  // frees every block of the heap
destroy_heap(level);                          // then park it for reuse
// x64 default allocator: DA :: #import "Default_Allocator"; DA.heap_free_all(xx h.data);
// arm64 macOS default allocator: no heaps at all (CREATE_HEAP asserts)
```

## Situation 3: unknown lifetime, known size (example 43)

Objects of one type that come and go at unpredictable times: entities, particles, connections, timers, graph nodes.
A pool of fixed-size slots with a free list fits this case. 0.2.032 ships none (`Bucket_Array` comes closest, see
below), so example 43 writes one in about 100 lines.

- **Chunks of slots.** Slots are carved from chunks taken from the pool's allocator; chunks never move, so pointers
  to live objects stay valid; only a small array of chunk pointers grows.
- **Intrusive free list.** A free slot stores the index of the next free slot in its own bytes (a `union` with the
  value), so the list costs no memory. Allocation pops the head, free pushes onto it: O(1), no search, no size lookup,
  no rounding to a size class (each slot adds 8 bytes, generation and index, plus any padding T's alignment needs).
  The slot freed last is reused first (example 43: freed in the order 4 0 1, handed out as 1 0 4), and it is the one
  most likely still in cache.

```jai
Slot :: struct (T: Type) {
    union {
        value:     T;
        next_free: s32;     // while the slot is free, its own bytes hold the free-list link
    }
    generation: u32;        // odd = live, even = free
    index:      u32;
}
```

- **Generational handles.** Reuse makes plain pointers and indices dangerous: after remove + add, an old reference
  points at the new occupant. A `Handle` is `(index, generation)`; each slot counts its lives (+1 on add, +1 on
  remove, so odd = live), and `pool_get` returns null unless the generations match. Example 43: the handle `{2, 1}`
  of a removed "orc" was rejected after "elf" took slot 2 as `{2, 3}`; after 1000 lives of one slot (generation 2000)
  all 1000 old handles were rejected; `Handle.{}` (generation 0, even) is never valid. Keep the generation counters
  for as long as handles may exist: example 45 keeps the entity slots for the whole game, and shows that slots
  re-created for a new level accept an old handle (generation counting restarts).
- **Iteration.** A `for_expansion` that skips free slots gives `for pool` and `remove it` (example 43 removes dead
  entities while iterating). It walks the slots in memory order, chunk by chunk: a linear scan, whatever the order of
  creation and removal was (example 45's lists show reused slots appearing early).
- **As an Allocator for one size.** ALLOCATE pops a slot (assert `size <= size_of(T)`), FREE pushes it back (put the
  value at offset 0 so the user pointer is the slot pointer), RESIZE within the slot returns the same pointer.
  Example 43: a queue doing 10000 pushes and pops of 16-byte nodes took 1 chunk of 64 slots from the heap; the same
  code on the default heap made 10050 allocations and 10050 frees.
- **Shipped relatives.** `Bucket_Array(T, items_per_bucket)`: buckets that never move, `bucket_array_add -> (locator,
  pointer)`, removal and slot reuse, `for` with `remove`. It finds a free slot by scanning occupied flags (from a
  per-bucket hint), and it has no generations: a stale locator silently finds the new occupant (example 43 prints
  it). It also **does not remember an allocator**: its `allocator` field is only read, so if you leave it unset each
  bucket comes from `context.allocator` at the time of the add, and `bucket_array_reset` frees the buckets with
  `context.allocator` at the time of the reset (probe: buckets allocated under A and B, reset under C: C received
  both bucket frees). Set `ba.allocator` before the first add. `Pool` (the module) is an arena, not an object pool.

## Situation 4: unknown lifetime, unknown size (example 44)

Strings of any length kept for unpredictable times, values shared between systems, user-driven data. This is what a
general-purpose heap is for.

- **How it works** (example 44 builds one as an Allocator): requests are rounded up to a **size class** (powers of
  two 16..1024 there); each class has its own LIFO free list linked through the free blocks; pages (64 KiB) serve one
  class each and are 64 KiB aligned, so FREE, which gets no size, finds the class by rounding the address down to
  the page header (rpmalloc does the same with its 64 KiB spans). Larger requests go to the backing heap. RESIZE gets
  `old_size` from the caller: stay in place while the class fits, otherwise allocate, copy, free. A `[..]`'s first
  growth arrives as **RESIZE with `old_memory = null`** (`array_reserve` calls `realloc`): handle it like ALLOCATE.
- **Internal fragmentation.** Rounding up wastes memory: example 44's eight requests (1696 bytes) occupy 2336 bytes in
  power-of-two classes (27% lost) and 1792 in rpmalloc 1.4.4's finer classes (5%). rpmalloc's block sizes, measured
  with `usable_size` (identical for the rpmalloc module on both platforms and the x64 default allocator): 1→16,
  17→32, 33→48, 100→112, 513→528, 1000→1008, 1024→1024, 1025→1536, 2000→2048, 5000→5120.
- **Stranded memory.** Free blocks of one class cannot serve another: after freeing 4000 blocks of 32 bytes,
  allocating 4000 × 64 bytes grew class 64 to 4 pages while class 32 kept its 2 pages of free blocks. Real heaps give
  a span back once all its blocks are free (source: the x64 default allocator caches one empty span per class and
  unmaps the others), but a single live block pins its span.
- **What ships.** `context.default_allocator`: on x64 (except iOS) a stripped-down rpmalloc 1.4.4 without thread
  caches (CAPS name "stripped-down rpmalloc 1.4.4 intended as Default_Allocator"; supports heaps and IS_THIS_YOURS);
  on arm64 macOS a wrapper over C `malloc`/`realloc`/`free` (its CAPS name, "Jai wrapper for C’s malloc/free/realloc
  functions.", contains a typographic apostrophe; CREATE_HEAP and IS_THIS_YOURS assert). Both are thread-safe. The
  `rpmalloc` module is the full allocator: thread caches, a global cache, heaps, statistics (module parameters;
  `ENABLE_STATISTICS`, `ENABLE_ASSERTS`, `ENABLE_VALIDATE_ARGS` default to true: set them false for release builds).
- **Write your own only for** a hard budget (fail at N bytes), per-subsystem statistics or leak accounting, a debug
  aid, or to drop everything one subsystem allocated in one call (example 44's `heap_release` frees all regions and
  large blocks; without `heap_free_all`, `destroy_heap` on rpmalloc does not). Otherwise use the default heap.
- Keep situation 4 small. how_to/200 argues that most data has a lifetime you can name; what is left is often
  strings and buffers whose owner frees them (example 45's chat lines: `sprint` on arrival, `free` when pushed out of
  a 3-line ring).

## How the allocator makes a data structure fast or slow

| Data structure | Fast with | Why | Slow or wrong with |
|---|---|---|---|
| tree, list, graph built and then dropped | arena (Flat_Pool, temp, chunk arena) | nodes adjacent in allocation order, no headers, no frees, one reset | default heap: one allocate and one free call per node, nodes scattered |
| `[..] T` that grows | `array_reserve` first, any allocator | one allocation, no copies | bump allocators without reserve: RESIZE copies and abandons the old buffer (Flat_Pool always, temp unless the padded size still fits; example 12: 20256 bytes for 500 strings) |
| objects others point at | arena or slot pool (stable addresses) | blocks never move | elements stored inside a growing `[..]`: they move, old pointers read stale copies (example 42) |
| many same-size objects with churn | slot pool + free list | O(1) reuse, the slot reused next was touched last (likely still cached), chunks contiguous | general heap: size-class lookup, a lock (the x64 default allocator locks the heap), objects spread over pages |
| references to objects that can die | generational handles | stale references detected | raw pointers or plain indices: silent use of a reused slot |
| per-frame scratch | `temp` | bump + one reset per frame; also free for library results | heap + `defer free`: two calls per object, fragmentation |
| columns of one table | one block carved into arrays | one allocation, SoA, alignment chosen | one allocation per column or per row |

The common thread: **contiguity** (neighbours in memory are processed together), **no per-object headers** (more
objects per cache line), **bulk free** (cost independent of count), **stable addresses** (pointers stay valid without
bookkeeping) and **free-list reuse** (the block handed out next was touched last, so it is likely still cached).

What it is worth, measured (reference/caches.md, -o, median of 7; Mac / powerslabs unless noted):
- **Allocation cost** (32-byte blocks): a slot pool called directly 1.1 / 0.9 ns per allocation (2.3 / 1.5 through an
  `Allocator_Proc`); `temp` 3.1 / 2.8 and Flat_Pool 4.7 / 4.1 with a free reset; rpmalloc 4.3 / 3.3; the default heap
  12.7 / 19.4 (and 72 ns per 256-byte block in big batches on x64).
- **Threads**: four threads allocating from the x64 default heap made each call 34× slower (one heap, one spin lock);
  rpmalloc or a Flat_Pool per thread stayed at 1.0–1.3×.
- **Walking**: a list whose nodes came from an arena (or from the heap in one run) walked 3–9× slower than summing an
  array at 128 MiB. **Churn scatters it**: after freeing half the nodes in random order and allocating replacements,
  the same list walked 20–90× slower (48–224 ns per node), close to a fully random order, for the slot pool and for the
  heap alike. Newest-first reuse is good for the next allocation and bad for the order of a long-lived structure.
  Scanning the pool's slots in memory order instead of following links ran 60–135× faster than that walk.
- **Fields per line**: reading 4 bytes of each 64-byte struct, SoA was 9–28× faster than AoS once the data left the
  caches; a loop that uses most fields can be slower in SoA.

So: allocate together what is walked together, iterate storage rather than links when order doesn't matter, rebuild
in order (copy into a fresh arena) after heavy churn, and keep the hot fields of hot loops in their own arrays.

## Relation to how_to/200's lifetime categories

how_to/200 sorts dynamic memory by lifetime alone: (1) dead by the end of the current function, (2) dead at a clear
point later (end of frame/request), (3) long-lived but owned by one subsystem, (4) long-lived with unclear ownership,
freed piece by piece; it treats (4) as rare and a hint to redesign, recommends temporary storage for (1) and (2), an
arena for (3) and keeping data by value inside its owner instead of separate allocations. Its categories answer the
first question of this guide; the second question (size known?) picks the tool within each:

| how_to/200 | here, size known | here, size unknown |
|---|---|---|
| (1) within a function | `[N] T` on the stack (situation 1) | `temp` + `auto_release_temp()`, or a mark (situation 2) |
| (2) clear end point | one exact block freed at that point (1) | `temp` reset there, Flat_Pool/arena reset there (2) |
| (3) owned by one subsystem | slot pool owned by it (3), or exact blocks (1) | the subsystem's own arena/heap, released when it ends (2) |
| (4) unclear ownership | slot pool + generational handles (3): ownership stays unclear, dangling references become detectable | default heap with `free` (4) |

Note the shift for category 3/4 data of one size: handles let you keep a fast, reusable pool even when nobody owns
the objects' lifetime.

## When NOT to build your own allocator

- The shipped ones already cover situations 2 and 4: `temp`, `Flat_Pool`, the default heap, rpmalloc. Write code
  first, push one of those, and measure before replacing it.
- Data owned by value inside its owner (a `[16] Slot` member, a struct inside a struct) needs no allocator at all.
- Threads: the examples here are single-threaded (none reports `MULTIPLE_THREADS`). Give each thread its own arena or
  pool, or use rpmalloc/the default heap; adding a Mutex to a bump allocator throws away most of its advantage.
- Debugging support: the memory debugger (`MEMORY_DEBUGGER=true`) ignores exactly three allocators, by procedure:
  Pool, Flat_Pool and temp. A custom arena is tracked like a heap, and resetting it by hand reports "Memory Debugging
  Error! We somehow got an allocation for an address that the memory debugging system thought was still live" for
  every reused address, and `report_memory_leaks()` then lists the last round's blocks as leaks (probe, Mac and
  powerslabs). Fix: answer DESTROY_HEAP with a reset and reset through Basic's `destroy_heap(arena_allocator)`: the
  debugger marks the blocks freed and stays quiet. A homemade pool also hides use-after-free from
  Overwriting_Allocator and Unmapping_Allocator unless you stamp freed slots yourself.

## Writing one: checklist (from examples 09, 42, 43, 44)

- Answer ALLOCATE (null = out of memory), RESIZE (including `old_memory = null` and copying
  `min(old_size, size)`), FREE (or ignore it and say so in CAPS), CAPS (fill the name when `old_memory` is non-null:
  `if old_memory { (cast(*string) old_memory).* = "name"; }`, braces required), IS_THIS_YOURS if you can. Assert on
  modes you don't support.
- Align the address, not the offset. 16 bytes matches the general heaps; temp and Flat_Pool use 8.
- Take your own bookkeeping memory (chunk lists, `[..]` of regions) from the backing allocator, never from yourself:
  set `regions.allocator = backing` (example 44) before the first add.
- `get_capabilities(a)` calls the proc with `allocator_data = null`: don't dereference data for CAPS.
- `f(x,, Allocator.{proc, data})` needs the type name: an untyped `.{proc, data}` after `,,` fails to compile
  ("Attempt to dereference type 'struct or array literal of unknown type'"). An Allocator whose `proc` is null is
  skipped by `,,` (since 0.1.080: "unset" means "keep context.allocator"), which is why containers with an unset
  allocator field work; `push_allocator(Allocator.{})` really installs it, and the next `alloc` crashes (macOS:
  SEGV_ACCERR, Linux: SEGV_MAPERR "Null Pointer Exception").
- Count calls in a wrapper while developing (examples 41–45 print counts instead of timings: they are deterministic).
