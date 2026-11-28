// PLATFORMS: linux
// JAI-ARGS: -x64
// EXPECT: built by the x64 backend on X64: sum of squares 1..1000 = 333833500
// Linux only: the compiler's own x64 backend generates code for x86-64 only. On an Apple Silicon Mac
// (target CPU ARM64) `-x64` fails with "The x64 backend supports only x64 CPUs but the CPU target was
// set to ARM64". It compiles much faster than the default LLVM backend (single object .build/<name>.o,
// codegen in milliseconds) but optimizes far less: use it for fast debug iterations, LLVM (default,
// or -o) for release builds. Results must not differ between backends; comparing them is a good probe.

#import "Basic";

main :: () {
    total := 0;
    for 1..1000  total += it * it;
    print("built by the x64 backend on %: sum of squares 1..1000 = %\n", CPU, total);
}
