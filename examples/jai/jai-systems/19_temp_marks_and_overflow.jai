// Scoped temp usage and what happens when temp storage is full (Basic, 0.2.032 paged implementation).
// - auto_release_temp() (a macro) rolls temp back to the current position at scope exit;
//   get_temporary_storage_mark() / set_temporary_storage_mark(mark) do the same by hand.
// - The first thread's storage is Build_Options.temporary_storage_size bytes (default 32768).
//   When a request does not fit, Basic allocates an OVERFLOW PAGE from ts.overflow_allocator
//   (or the default allocator) of max(request, page size) bytes; the rest of the old page is
//   abandoned. Overflow pages are freed by reset/marks. Nothing fails, it just gets slower,
//   so size the storage (example 21) so that a typical frame never overflows.
// Inspect the paged details by casting context.temporary_storage to *Temporary_Storage_Paged_Alloc.
// EXPECT: start: page 32768, used 0, overflow pages 0
// EXPECT: inside auto_release_temp: used 8000, overflow pages 0
// EXPECT: after the scope: page 32768, used 0, overflow pages 0
// EXPECT: after a 100000-byte request: page 100000, used 100000, overflow pages 1
// EXPECT: after set_temporary_storage_mark: page 32768, used 0, overflow pages 0
// EXPECT: after 5 x 20000 bytes: used 100000, overflow pages 4, high water 100000
// EXPECT: after reset: used 0, overflow pages 0, high water 0
#import "Basic";

state :: (label: string) {
    ts := cast(*Temporary_Storage_Paged_Alloc) context.temporary_storage;
    pages := 0;
    p := ts.overflow_pages;
    while p { pages += 1; p = p.next; }
    print("%: page %, used %, overflow pages %\n", label, ts.size, ts.total_bytes_occupied, pages);
}

main :: () {
    state("start");
    {
        auto_release_temp();
        for 1..1000 talloc(8);
        ts := cast(*Temporary_Storage_Paged_Alloc) context.temporary_storage;
        print("inside auto_release_temp: used %, overflow pages %\n", ts.total_bytes_occupied, ifx ts.overflow_pages then 1 else 0);
    }
    state("after the scope");

    mark := get_temporary_storage_mark();
    talloc(100_000);                    // bigger than the whole first page
    state("after a 100000-byte request");
    set_temporary_storage_mark(mark);
    state("after set_temporary_storage_mark");

    for 1..5 talloc(20_000);            // only one fits per page: 4 overflow pages
    ts := cast(*Temporary_Storage_Paged_Alloc) context.temporary_storage;
    pages := 0;
    p := ts.overflow_pages;
    while p { pages += 1; p = p.next; }
    print("after 5 x 20000 bytes: used %, overflow pages %, high water %\n", ts.total_bytes_occupied, pages, ts.high_water_mark);
    reset_temporary_storage();
    print("after reset: used %, overflow pages %, high water %\n", ts.total_bytes_occupied, ifx ts.overflow_pages then 1 else 0, ts.high_water_mark);
}
