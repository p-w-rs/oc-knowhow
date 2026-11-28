// The classic temporary-storage bug: keeping a tprint/temp pointer past reset_temporary_storage.
// Without help the stale string often still "works" (the bytes are not erased) until something
// else allocates over it. Basic's program parameter TEMP_ALLOCATOR_OVERWRITE_MEMORY=true
// stamps reset/marked/freed temp memory (0xdb after a reset), so stale use shows garbage at once.
// Turn it on in debug builds; the fix is to copy_string() what must survive a reset.
// EXPECT: before reset: "player_1" (8 bytes)
// EXPECT: after reset the stale bytes are 0xdb: true
// EXPECT: the copy is fine: "player_1"
#import "Basic"()(TEMP_ALLOCATOR_OVERWRITE_MEMORY = true);

main :: () {
    name := tprint("player_%", 1);
    kept := copy_string(name);          // survives: default allocator
    print("before reset: \"%\" (% bytes)\n", name, name.count);

    reset_temporary_storage();

    // 'name' still has its count and pointer, but its bytes were overwritten:
    print("after reset the stale bytes are 0xdb: %\n", name.data[0] == 0xdb);
    print("the copy is fine: \"%\"\n", kept);
}
