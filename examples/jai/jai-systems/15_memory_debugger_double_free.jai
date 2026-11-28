// With MEMORY_DEBUGGER=true a double free is reported with three stack traces: the bad free,
// the earlier free, and the allocation. MEMORY_DEBUGGER_REPORT_ASSERTS=true (since 0.2.031) makes
// the debugger assert right after the report, so the program stops at the first problem instead
// of continuing into the underlying allocator (C malloc on macOS traps on a double free; the
// x64 default allocator does not). The report goes to stdout, the assertion to stderr.
// EXPECT-EXIT: 1
// EXPECT-CONTAINS: Attempt to call Basic.free() on memory that was already freed.
// EXPECT-CONTAINS: Here is how
// EXPECT-CONTAINS: was first allocated:
// EXPECT-CONTAINS: Assertion failed
#import "Basic"()(MEMORY_DEBUGGER=true, MEMORY_DEBUGGER_REPORT_ASSERTS=true);

Buffer :: struct { bytes: [64] u8; }

release :: (b: *Buffer) { free(b); }

main :: () {
    b := New(Buffer);
    release(b);
    print("releasing again...\n");
    release(b);                            // bug: second free of the same block
    print("not reached\n");
}
