// #if needs a compile-time constant. A variable declared with := is never constant, even when its
// value looks obvious. Declare it with :: (or use a module parameter / #run result) instead.
// EXPECT-COMPILE-ERROR: Condition of #if is not constant.

#import "Basic";

main :: () {
    verbose := true;              // fix: verbose :: true;
    #if verbose  print("verbose mode\n");
}
