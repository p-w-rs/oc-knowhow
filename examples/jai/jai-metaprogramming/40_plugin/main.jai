// Plugins extend the default metaprogram without writing a build file:
//     jai main.jai +Note_Counter -note Audit +Autorun
// Each `+Name` loads module Name as a plugin and gives it the arguments up to the next `+`.
// Plugin arguments must come last (after normal compiler flags). Bundled plugins include Check
// (always on unless -no_check), Autorun (runs the program after a successful build), Program_Print
// and Codex; modules/Example_Plugin.jai is a template.
// Pitfall: if a plugin's init() fails the compiler prints "A plugin init() failed. Exiting." but
// exits with status 0 (0.2.032), so CI scripts must not rely on the exit code alone.
// JAI-ARGS: +Note_Counter -note Audit +Autorun
// EXPECT-COMPILE: [Note_Counter] @Audit: delete_save, export_report (2)
// EXPECT-COMPILE: [Autorun] Running:
// EXPECT-COMPILE: main program ran
// EXPECT: main program ran

#import "Basic";

export_report :: () {} @Audit
delete_save   :: () {} @Audit
load_assets   :: () {}

main :: () {
    print("main program ran\n");
}
