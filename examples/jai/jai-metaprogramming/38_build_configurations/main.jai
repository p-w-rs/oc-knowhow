// The executable of the build. BUILD_KIND is not declared here: build.jai adds it as a string,
// so the program knows how it was built without a preprocessor.
#import "Basic";

main :: () {
    print("app built as % (bounds checks %)\n", BUILD_KIND, BOUNDS_CHECKS);
}
