// On an arm64 Mac, an unguarded #asm block does not compile (the x64 backend is unavailable too:
// "jai -x64 f.jai" fails with "The x64 backend supports only x64 CPUs but the CPU target was set
// to ARM64"). Guard x64-only code with #if CPU == .X64 (example 31).
// PLATFORMS: macos
// EXPECT-COMPILE-ERROR: The target of this workspace does not support x64 asm.
#import "Basic";

main :: () {
    x := 10;
    #asm { add x, 5; }
    y := x;
    print("y = %\n", y);
}
