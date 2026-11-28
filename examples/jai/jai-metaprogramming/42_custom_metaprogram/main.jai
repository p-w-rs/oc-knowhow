// An ordinary program, compiled by a custom metaprogram instead of the default one
// (see meta/My_Meta.jai). `jai -- help` (in a terminal) lists the developer options:
// import_dir, meta, no_jobs, randomize, seed, extra, chaos.
// JAI-ARGS: --- import_dir meta meta My_Meta
// EXPECT-COMPILE: [My_Meta] building 'main' from 1 file(s)
// EXPECT-COMPILE: [My_Meta] main program procedures: helper, main
// EXPECT: built by My_Meta, helper says 7

#import "Basic";

helper :: () -> int { return 7; }

main :: () {
    print("built by My_Meta, helper says %\n", helper());
}
