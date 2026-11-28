// The frame pattern: allocate freely from temp during a frame (or request, or file), copy out
// only what must survive with a real allocator, reset once per iteration.
// Watch high_water_mark to size temporary storage; it is reset to 0 by reset_temporary_storage.
// EXPECT: frame 1: 3 labels, temp used 96, kept "frame 1 best: score 30"
// EXPECT: frame 2: 3 labels, temp used 96, kept "frame 2 best: score 60"
// EXPECT: frame 3: 3 labels, temp used 96, kept "frame 3 best: score 90"
// EXPECT: kept across frames: 3 strings, temp used after the loop: 0
#import "Basic";

score_labels :: (frame: int) -> [] string {
    labels: [..] string;
    labels.allocator = temp;
    array_reserve(*labels, 3);
    for 1..3 array_add(*labels, tprint("score %", it * 10 * frame));
    return labels;
}

main :: () {
    kept: [..] string;                       // long-lived: default allocator
    for frame: 1..3 {
        labels := score_labels(frame);
        best := tprint("frame % best: %", frame, labels[labels.count-1]);
        array_add(*kept, copy_string(best));  // copy out of temp before the reset
        print("frame %: % labels, temp used %, kept \"%\"\n", frame, labels.count,
            context.temporary_storage.total_bytes_occupied, kept[kept.count-1]);
        reset_temporary_storage();           // labels and best are dead from here on
    }
    print("kept across frames: % strings, temp used after the loop: %\n", kept.count, context.temporary_storage.total_bytes_occupied);
}
