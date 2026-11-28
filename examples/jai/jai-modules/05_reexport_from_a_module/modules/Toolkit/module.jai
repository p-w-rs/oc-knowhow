// Re-export everything from Basic, and also the name 'Basic' itself.
using Basic :: #import "Basic";

// Re-export one procedure (group) under a new name.
say :: Basic.print;

toolkit_hello :: () { print("[toolkit] ready\n"); }
