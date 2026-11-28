// modules/Unmapping_Allocator gives every allocation its own pages, placed so the block ENDS at a
// page boundary followed by an inaccessible page, and makes freed pages inaccessible.
// Reads past the end and use-after-free crash at the faulting instruction (debug builds only:
// it is slow and the page table keeps growing). Pool can use it with #import "Pool"()(USE_UNMAPPING_ALLOCATOR=true).
// The crash handler's wording is misleading here: Linux reports SEGV_ACCERR "write to read-only
// memory" (even for a read), macOS reports SIGBUS "invalid address alignment". Exit code 1.
// EXPECT-EXIT: 1
// EXPECT-CONTAINS: last valid byte written
// EXPECT-CONTAINS: The program crashed because
#import "Basic";
#import "Unmapping_Allocator";

main :: () {
    context.allocator = get_unmapping_allocator();
    buffer := cast(*u8) alloc(100);
    buffer[99] = 7;
    print("last valid byte written\n");
    buffer[100] = 7;                       // one past the end: the guard page faults here
    print("not reached\n");
}
