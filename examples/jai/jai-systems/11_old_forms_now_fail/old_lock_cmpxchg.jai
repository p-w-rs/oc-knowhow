// Removed in 0.2.009: the compare_and_swap intrinsic returns (success, old_value).
#import "Basic";
main :: () { x: s64 = 1; lock_cmpxchg(*x, 1, 2); }
