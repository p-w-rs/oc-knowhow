// Using a third-party module: copy (vendor) it into a folder of your project and
// add that folder to the search path (-import_dir, or Build_Options.import_path in
// a build.jai; a ./modules folder next to the first file works without flags).
// Community modules track the compiler, so expect small breaks after an upgrade:
// 0.2.032 renamed the 'initialized' parameter of New/NewArray to 'initialize' with
// no deprecation period, which broke several maintained public repositories. The
// error points into the vendored file; fix the copy (one word) or update upstream.
// This Old_Grid module is a stand-in written for this example.
// JAI-ARGS: -import_dir third_party
// EXPECT-COMPILE-ERROR: Argument name 'initialized' (number 3) is not found in the procedure being called.

#import "Basic";
#import "Old_Grid";

main :: () {
    g := make_grid(4, 3);
    print("% cells\n", g.cells.count);
}
