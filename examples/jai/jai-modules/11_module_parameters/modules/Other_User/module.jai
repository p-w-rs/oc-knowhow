// Another module importing Counter without parameters: it gets the same default
// instance as the main program's plain import, including VERBOSE = true.
C :: #import "Counter";
bump_from_elsewhere :: () -> int { return C.bump(); }
