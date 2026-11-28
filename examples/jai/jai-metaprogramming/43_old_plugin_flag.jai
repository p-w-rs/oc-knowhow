// Old command lines: plugins used to be loaded with `-plug Name` (or `-plugin Name`); since 0.2.012
// they are `+Name args...` at the END of the command line (see 40_plugin). how_to/495 still shows
// `-plug`. Old metaprogram arguments after `--` must now follow a lone `-`
// (`jai build.jai - release`); `--` is reserved for compiler developer options
// ("Unknown developer option 'release'").
// Current form of this command:  jai 43_old_plugin_flag.jai +Autorun
// JAI-ARGS: -plug Autorun
// EXPECT-COMPILE-ERROR: Unknown argument '-plug'.

#import "Basic";

main :: () {
    print("never built\n");
}
