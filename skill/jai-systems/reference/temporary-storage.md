# Temporary storage (deep dive)

Verified on Jai beta 0.2.032 (macOS arm64, Linux x86-64). Examples: `examples/jai/jai-systems/18`–`22`.
Sources: `how_to/012_temporary_storage.jai`, `how_to/200_memory_management.jai` (patterns a–c),
`modules/Basic/Temporary_Storage_Paged_Alloc.jai` (the implementation; the 0.2.029 changelog calls it
`Temporary_Allocator.jai`, which does not exist), `modules/Runtime_Support.jai` (`Temporary_Storage`, the first
thread's buffer), `modules/Thread/primitives.jai` (per-thread storage). Library:
`library_search query="auto_release_temp set_temporary_storage_mark" sources=["jai-modules-src"]`.

## The model

- Every thread has a bump allocator at `context.temporary_storage`. Allocating is a pointer bump (8-byte aligned);
  `free` does nothing; everything is released at once with `reset_temporary_storage()` or rolled back to a mark.
- You pick the reset point: a moment when nothing temporary is alive (end of a frame, a request, a file, an iteration).
  Then temp memory is like garbage-collected memory with an explicit, cheap, predictable collection.
- Because it is in the context, libraries can return temp results without owning them, and the caller decides
  how long they live (until its next reset). Basic and other modules do this (list below).
- `temp` (= `temporary_allocator`, `Allocator.{temporary_allocator_proc, null}`) is an ordinary Allocator, so anything
  that allocates can use it: `New(T,, temp)`, `array.allocator = temp`, `push_allocator(temp)` for a whole call tree.

## API (Basic)

| Call | Effect |
|---|---|
| `tprint(fmt, args..)` | print into temp memory (`sprint` uses `context.allocator`) |
| `talloc(n)` (= `temporary_alloc`) | n bytes of temp memory; calls the temp proc directly |
| `temp_c_string(s)` | NUL-terminated copy in temp (for C calls) |
| `New(T,, temp)`, `NewArray(n, T,, temp)`, `copy_string(s,, temp)` | any allocating call, redirected for one call |
| `arr.allocator = temp` | a `[..]` that grows in temp (set before the first add) |
| `reset_temporary_storage()` | release everything: frees overflow pages, zeroes `total_bytes_occupied` and `high_water_mark` |
| `mark := get_temporary_storage_mark(); ...; set_temporary_storage_mark(mark)` | roll back to a point (frees overflow pages allocated since) |
| `auto_release_temp()` | macro: takes a mark now and restores it at the end of the enclosing scope |
| `context.temporary_storage.total_bytes_occupied`, `.high_water_mark`, `.size` | usage counters (read `high_water_mark` before a reset) |

`Temporary_Storage` fields: `data, size, total_bytes_occupied, high_water_mark, last_set_mark_location`, and 256 bytes
of `implementation_data` that Basic overlays with `Temporary_Storage_Paged_Alloc` (`overflow_allocator`,
`overflow_pages`, `original_data`, `original_size`, `current_page_bytes_occupied`). Cast to that type to look inside
(examples 19, 21).

## Size and overflow (measured)

- Main thread: a static buffer in the executable of `Build_Options.temporary_storage_size` bytes (default 32768,
  aligned 64). Set it in a build metaprogram (example 21: 1 MiB, then 200 KiB of temp use without overflow).
- Threads: `thread_init(*t, proc, temporary_storage_size = 16384)` allocates the buffer from the creating thread's
  allocator (freed by `thread_deinit`), or `starting_storage = *some_storage` to supply your own (copied by value).
  `Thread_Group` `init(..., temporary_storage_size = 16384)` applies to all workers.
- When a request does not fit in the current page, Basic allocates an **overflow page** from
  `ts.overflow_allocator` (default: `Context_Base.default_allocator`; verified that a custom one receives the page
  allocations and the frees on reset) of max(request, first page size − 32 header bytes); the unused tail of the
  previous page is abandoned. Measured with a 32768-byte first page: a 100000-byte request makes one 100000-byte page;
  then five 20000-byte requests use 4 overflow pages (only one fits per page).
- Nothing fails on overflow; the frame just starts calling the heap. A reset or mark frees the pages again. Size the
  storage so a normal frame stays in the first page: log `high_water_mark` before resetting.
- RESIZE in temp: if the new size fits the old padded size it returns the same block, otherwise it allocates a new
  block and copies (even when the block is the last one). A `[..]` growing in temp therefore leaves its old buffers
  behind: 100 ints added one by one used 1984 bytes; `array_reserve` first (example 18 reserves).

## Patterns

- Frame/request loop (example 20): allocate freely; before the reset, copy out what must survive with a real
  allocator (`copy_string(s)`, `array_copy`, `New` on the heap); reset once per iteration.
- Scoped scratch inside a long frame: `auto_release_temp();` at the top of a procedure or block that makes a lot of
  temporary data you won't return (parsing a file, building a big string). Don't return temp memory from such a scope.
- Returning results: a procedure may return temp memory (`tprint`, a temp array) to its caller; document it like
  Basic does ("/* Temporary_Storage */" in the signature comment) and let the caller copy if it keeps it.
- Whole subsystem on temp: `push_allocator(temp)` around a call into code that allocates and never frees; its results
  live until your reset.

## What returns temp memory (0.2.032)

`tprint`, `temp_c_string`, `talloc_string`, `get_stack_trace_strings`, `enum_values_as_enum`, the message passed to
loggers by `log`, `Thread_Group`'s `get_completed_work` (in the caller's temp), `calendar_to_string` and
`calendar_to_iso_string`, `System.get_path_of_running_executable`, `System.get_error_string` and the description of
`System.get_error_value_and_string` (Unix: a temp copy). Basic marks such results with a `/* Temporary_Storage */`
comment after the return type: grep for it, and check a procedure's source before keeping its result.

## Pitfalls

- **Stale temp pointers**: after a reset the bytes stay until something reuses them, so the bug is invisible. In
  debug builds `#import "Basic"()(TEMP_ALLOCATOR_OVERWRITE_MEMORY = true);` stamps memory: 0xdb over the page on reset,
  0xda over the rolled-back part on `set_temporary_storage_mark`, 0xdc over freed overflow pages (example 22 checks
  0xdb). The parameter was `TEMP_ALLOCATOR_POISON_FREED_MEMORY` before 0.2.028 (the old name is now an error).
- **No temporary storage**: in a context from `push_context { }` (C callbacks, foreign threads) `temporary_storage`
  is null and temp falls back to `context.allocator` (the heap). Those allocations are never freed: `free` is a no-op
  for temp and there is nothing to reset. Push a saved context instead, or give the callback its own storage.
- **Threads**: each thread's storage is private. Don't hand temp memory to another thread unless it is done with it
  before your reset, and don't reset another thread's storage. Temp is not `MULTIPLE_THREADS`.
- **Temp in long-lived containers**: a Hash_Table or `[..]` that remembered `temp` keeps using it after the reset:
  dangling data. Set the allocator explicitly for long-lived containers.
- **The memory debugger ignores temp** (and Pool/Flat_Pool): leaks there are not reported; use the counters.
- 0.2.029 had a regression (fixed in 0.2.030): a reset or mark before the first overflow made temp allocate tiny
  pages from then on. If you are on 0.2.029, upgrade.

## Old code

| Old | Current |
|---|---|
| `__temporary_allocator` | `temp` (removed in 0.2.029: "Undeclared identifier '__temporary_allocator'.") |
| `Push_Temporary();` | `auto_release_temp();` (Push_Temporary removed in 0.1.028) |
| `alloc(n, temp)`, `copy_string(s, temp)` | `alloc(n,, temp)`, `copy_string(s,, temp)` (0.1.080) |
| `TEMP_ALLOCATOR_POISON_FREED_MEMORY` | `TEMP_ALLOCATOR_OVERWRITE_MEMORY` (0.2.028) |
| String's `split` returning temp by default | `split(s, sep,, temp)` (0.1.080) |
