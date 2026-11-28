// Situation 4 of 4: you know neither HOW LONG nor HOW MUCH. That is the job of a general-purpose
// heap. To see how one works and what it costs, here is a small one written as a Jai Allocator.
// - Segregated free lists: each request is rounded up to a size class (powers of two, 16..1024);
//   every class has its own LIFO list of free blocks, linked through the free blocks themselves.
//   ALLOCATE pops, FREE pushes: O(1), and a block freed a moment ago is reused while it is
//   still in cache.
// - Pages: 64 KiB, each serving one class, carved lazily with a bump pointer per class. Pages
//   are 64 KiB ALIGNED (taken 16 at a time from the backing heap, plus one page of slack to
//   align them), so FREE, which gets no size, finds a block's class by rounding the address down
//   to its page header: no header per block. (rpmalloc does the same with its 64 KiB spans.)
// - Requests over 1024 bytes go to the backing heap behind a 32-byte header that links them into
//   a list, so FREE, IS_THIS_YOURS and heap_release can find them.
// - RESIZE gets old_size from the caller: a new size that still fits the block's class stays in
//   place; otherwise allocate, copy min(old_size, size) bytes, free. A [..]'s first growth
//   arrives as RESIZE with old_memory = null: treat it like ALLOCATE.
// - Costs on display: internal fragmentation (rounding up to the class), memory stranded in a
//   class (free 32-byte blocks cannot serve 64-byte requests; real heaps hand a page whose blocks
//   are all free back: the x64 default allocator keeps one empty 64 KiB span per class and unmaps
//   the rest), no thread safety (CAPS leaves out MULTIPLE_THREADS).
// When to just use what ships: nearly always. The default heap already is a size-class heap on
// x64 (a stripped-down rpmalloc 1.4.4 without thread caches, with the same block sizes as the
// rpmalloc module printed below) and wraps C malloc on arm64 macOS; the rpmalloc module adds
// thread caches and heaps. Write your own for a hard memory budget, per-subsystem statistics, a
// debugging aid, or to drop everything a subsystem allocated in one call (heap_release below).
// EXPECT: classes 16 32 64 128 256 512 1024; larger requests go to the backing heap behind a 32-byte header
// EXPECT: requested -> our class / rpmalloc 1.4.4 block: 1->16/16 8->16/16 17->32/32 24->32/32 33->64/48 100->128/112 513->1024/528 1000->1024/1008
// EXPECT: those 8 requests: 1696 bytes; our classes hand out 2336 (27% lost to rounding), rpmalloc's 1792 (5%)
// EXPECT: 300 names via sprint: 2890 bytes requested, 300 blocks of class 16 = 4800 bytes
// EXPECT: [..] int of 300: 7 growths, 1 of them a RESIZE with old_memory = null; the last block (4096 bytes) is a large one
// EXPECT: a freed block is reused at once (LIFO): true
// EXPECT: realloc 30 -> 32 bytes stayed in place: true; 32 -> 33 moved to class 64: true
// EXPECT: 4000 x 32 bytes freed, then 4000 x 64 allocated: class 32 keeps its 2 pages of free blocks, class 64 grows to 4 pages
// EXPECT: IS_THIS_YOURS: small block true, large block true, default-heap block false
// EXPECT: caps: example size-class heap | FREE | ACTUALLY_RESIZE | IS_THIS_YOURS | HINT_I_AM_A_GENERAL_HEAP_ALLOCATOR
// EXPECT: heap_release: backing heap blocks still live: 0 (regions 1, large blocks 3 freed in one call)
#import "Basic";
rp :: #import "rpmalloc";

CLASS_SIZES   :: int.[16, 32, 64, 128, 256, 512, 1024];
CLASS_COUNT   :: CLASS_SIZES.count;
SMALL_LIMIT   :: 1024;
PAGE_SIZE     :: 64 * 1024;
PAGE_HEADER   :: 64;              // multiple of 16: blocks stay 16-byte aligned
REGION_PAGES  :: 16;

Page :: struct {                  // lives in the first PAGE_HEADER bytes of every page
    class_index: int;
}

Free_Block :: struct { next: *Free_Block; }

Large :: struct {                 // 32 bytes in front of every large block
    prev, next: *Large;
    size:       int;
    unused:     int;
}

Region :: struct { raw: *void; first_page: *u8; }

Size_Class_Heap :: struct {
    backing:      Allocator;                  // regions and large blocks come from here
    free_lists:   [CLASS_COUNT] *Free_Block;
    carve, carve_end: [CLASS_COUNT] *u8;      // bump range in the page each class is carving
    regions:      [..] Region;                // its memory comes from 'backing' too, never from us
    next_page, region_end: *u8;
    pages:        int;
    class_pages:  [CLASS_COUNT] int;
    large:        *Large;
    // statistics, for this example
    live_blocks:  [CLASS_COUNT] int;
    growths, resize_from_null: int;
}

heap_init :: (h: *Size_Class_Heap, backing: Allocator) {
    h.backing = backing;
    h.regions.allocator = backing;            // our own bookkeeping must not allocate from us
}

class_for :: (size: int) -> int {
    for CLASS_SIZES  if size <= it  return it_index;
    return -1;
}

new_page :: (h: *Size_Class_Heap, class_index: int) -> *Page {
    if h.next_page == h.region_end {
        raw := h.backing.proc(.ALLOCATE, (REGION_PAGES + 1) * PAGE_SIZE, 0, null, h.backing.data);
        if !raw  return null;
        first := cast(*u8) ((cast(int) raw + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1));
        array_add(*h.regions, .{raw, first});
        h.next_page, h.region_end = first, first + REGION_PAGES * PAGE_SIZE;
    }
    page := cast(*Page) h.next_page;
    h.next_page += PAGE_SIZE;
    page.class_index = class_index;
    h.pages += 1;
    h.class_pages[class_index] += 1;
    return page;
}

page_of :: (h: *Size_Class_Heap, p: *void) -> *Page {
    for h.regions {
        if p >= it.first_page && p < it.first_page + REGION_PAGES * PAGE_SIZE
            return cast(*Page) (cast(int) p & ~(PAGE_SIZE - 1));
    }
    return null;                               // not in our pages: a large block, or not ours
}

allocate :: (h: *Size_Class_Heap, size: int) -> *void {
    c := class_for(size);
    if c < 0 {
        l := cast(*Large) h.backing.proc(.ALLOCATE, size_of(Large) + size, 0, null, h.backing.data);
        if !l  return null;
        l.prev, l.next, l.size = null, h.large, size;
        if h.large  h.large.prev = l;
        h.large = l;
        return l + 1;
    }
    h.live_blocks[c] += 1;
    if h.free_lists[c] {                       // reuse the block freed last
        b := h.free_lists[c];
        h.free_lists[c] = b.next;
        return b;
    }
    if h.carve_end[c] - h.carve[c] < CLASS_SIZES[c] {
        page := new_page(h, c);
        if !page { h.live_blocks[c] -= 1; return null; }
        h.carve[c], h.carve_end[c] = cast(*u8) page + PAGE_HEADER, cast(*u8) page + PAGE_SIZE;
    }
    result := h.carve[c];
    h.carve[c] += CLASS_SIZES[c];
    return result;
}

deallocate :: (h: *Size_Class_Heap, p: *void) {
    if !p  return;
    page := page_of(h, p);
    if page {
        c := page.class_index;
        b := cast(*Free_Block) p;
        b.next = h.free_lists[c];
        h.free_lists[c] = b;
        h.live_blocks[c] -= 1;
        return;
    }
    l := cast(*Large) p - 1;
    if l.prev  l.prev.next = l.next;  else h.large = l.next;
    if l.next  l.next.prev = l.prev;
    h.backing.proc(.FREE, 0, 0, l, h.backing.data);
}

reallocate :: (h: *Size_Class_Heap, p: *void, size: int, old_size: int) -> *void {
    h.growths += 1;
    if !p { h.resize_from_null += 1; return allocate(h, size); }
    page := page_of(h, p);
    if page && size <= CLASS_SIZES[page.class_index]  return p;      // still fits its block
    if !page && class_for(size) < 0 {                                 // large to large: let the backing heap do it
        l := cast(*Large) p - 1;
        moved := cast(*Large) h.backing.proc(.RESIZE, size_of(Large) + size, size_of(Large) + l.size, l, h.backing.data);
        if !moved  return null;
        moved.size = size;
        if moved.prev  moved.prev.next = moved;  else h.large = moved;
        if moved.next  moved.next.prev = moved;
        return moved + 1;
    }
    result := allocate(h, size);
    if result { memcpy(result, p, min(old_size, size)); deallocate(h, p); }
    return result;
}

is_mine :: (h: *Size_Class_Heap, p: *void) -> bool {
    if page_of(h, p)  return true;
    l := h.large;
    while l { if p == cast(*void) (l + 1)  return true; l = l.next; }
    return false;
}

heap_release :: (h: *Size_Class_Heap) -> regions: int, large_blocks: int {
    regions, large_blocks := h.regions.count, 0;
    while h.large { next := h.large.next; h.backing.proc(.FREE, 0, 0, h.large, h.backing.data); h.large = next; large_blocks += 1; }
    for h.regions  h.backing.proc(.FREE, 0, 0, it.raw, h.backing.data);
    array_reset(*h.regions);
    backing := h.backing;
    h.* = .{};
    heap_init(h, backing);
    return regions, large_blocks;
}

size_class_heap_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    h := cast(*Size_Class_Heap) data;
    if mode == {
      case .ALLOCATE;      return allocate(h, size);
      case .RESIZE;        return reallocate(h, old_memory, size, old_size);
      case .FREE;          deallocate(h, old_memory); return null;
      case .IS_THIS_YOURS; return cast(*void) cast(int) is_mine(h, old_memory);
      case .CAPS;
        if old_memory { (cast(*string) old_memory).* = "example size-class heap"; }
        return cast(*void) (Allocator_Caps.FREE | .ACTUALLY_RESIZE | .IS_THIS_YOURS | .HINT_I_AM_A_GENERAL_HEAP_ALLOCATOR);
      case .STARTUP; #through;
      case .SHUTDOWN;      return null;
      case;
        assert(false, "size-class heap: mode % is not supported", mode);
        return null;
    }
}

// Backing heap with a live-block count, to prove that heap_release gives everything back.
Backing_Count :: struct { live: int; }
counting_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    c := cast(*Backing_Count) data;
    if mode == .ALLOCATE || (mode == .RESIZE && !old_memory)  c.live += 1;
    if mode == .FREE && old_memory  c.live -= 1;
    return context.default_allocator.proc(mode, size, old_size, old_memory, null);
}

main :: () {
    backing_count: Backing_Count;
    heap: Size_Class_Heap;
    heap_init(*heap, .{counting_proc, *backing_count});
    a := Allocator.{size_class_heap_proc, *heap};

    print("classes");
    for CLASS_SIZES  print(" %", it);
    print("; larger requests go to the backing heap behind a %-byte header\n", size_of(Large));

    // Internal fragmentation: what a request really costs, here and in rpmalloc.
    rp.rpmalloc_allocator_proc(.STARTUP, 0, 0, null, null);
    rpa := Allocator.{rp.rpmalloc_allocator_proc, null};
    requests :: int.[1, 8, 17, 24, 33, 100, 513, 1000];
    asked, ours, theirs := 0, 0, 0;
    print("requested -> our class / rpmalloc 1.4.4 block:");
    for requests {
        p := alloc(it,, rpa);
        r := rp.usable_size(p);
        free(p,, rpa);
        c := CLASS_SIZES[class_for(it)];
        print(" %->%/%", it, c, r);
        asked += it; ours += c; theirs += r;
    }
    print("\n");
    print("those % requests: % bytes; our classes hand out % (%\% lost to rounding), rpmalloc's % (%\%)\n",
        requests.count, asked, ours, (ours - asked) * 100 / ours, theirs, (theirs - asked) * 100 / theirs);

    // Ordinary code on top of it: strings and a [..], through push_allocator.
    names: [] string;
    numbers: [..] int;
    {
        push_allocator(a);
        names = NewArray(300, string);                  // 4800 bytes: a large block
        for 0..299  names[it] = sprint("player_%", it);
        for 1..300  array_add(*numbers, it);
    }
    requested := 0;
    for names  requested += it.count;
    print("% names via sprint: % bytes requested, % blocks of class 16 = % bytes\n",
        names.count, requested, heap.live_blocks[0], heap.live_blocks[0] * 16);
    print("[..] int of %: % growths, % of them a RESIZE with old_memory = null; the last block (% bytes) is a large one\n",
        numbers.count, heap.growths, heap.resize_from_null, numbers.allocated * size_of(int));

    p := alloc(24,, a);
    free(p,, a);
    q := alloc(30,, a);
    print("a freed block is reused at once (LIFO): %\n", p == q);

    r := realloc(q, 32, 30,, a);
    s := realloc(r, 33, 32,, a);
    print("realloc 30 -> 32 bytes stayed in place: %; 32 -> 33 moved to class 64: %\n", r == q, page_of(*heap, s).class_index == 2);
    free(s,, a);

    // Stranded memory: free blocks of one class are useless to another.
    small: [4000] *void;
    for 0..3999  small[it] = alloc(32,, a);
    for small  free(it,, a);
    for 0..3999  small[it] = alloc(64,, a);
    print("4000 x 32 bytes freed, then 4000 x 64 allocated: class 32 keeps its % pages of free blocks, class 64 grows to % pages\n",
        heap.class_pages[1], heap.class_pages[2]);
    for small  free(it,, a);

    big := alloc(5000,, a);
    foreign := alloc(16);                               // default heap
    yours :: (x: *void) -> bool #expand { return a.proc(.IS_THIS_YOURS, 0, 0, x, a.data) != null; }
    print("IS_THIS_YOURS: small block %, large block %, default-heap block %\n", yours(names[0].data), yours(big), yours(foreign));
    free(foreign);

    caps, name := get_capabilities(a);
    print("caps: % | %\n", name, caps);

    // No frees needed for names, numbers or big: the heap can drop everything at once.
    regions, large_blocks := heap_release(*heap);
    print("heap_release: backing heap blocks still live: % (regions %, large blocks % freed in one call)\n",
        backing_count.live, regions, large_blocks);
}
