// Inline assembly (#asm) is x86-64 only in 0.2.032: registers are named like variables and
// allocated by the compiler, operand size goes on the mnemonic (mov.32, popcnt?T), and
// instructions beyond the build's feature set need a feature list (#asm AVX2 { ... }) plus a
// runtime check (Machine_X64: get_cpu_info + check_feature). On arm64 an #asm block is a
// compile error (or compiles to nothing, example 33): guard it with #if CPU == .X64 + a fallback.
// For common bit tricks prefer modules/Bit_Operations (popcount, bit_scan_forward/reverse,
// byte_swap): it already does exactly this (x64 asm, plain loops elsewhere).
// An #asm operand must stay register-only: if its address is taken (print takes it) the asm is
// silently dropped (example 33); add_five returns the value, which is fine.
// EXPECT: add via #asm or fallback: 15
// EXPECT: popcount(0xF0F0): 8
// EXPECT: bit_scan_forward(0b1000): 4, of 0: 0
// EXPECT: bit_scan_reverse(0x80): 8
// EXPECT: byte_swap(0x11223344): 0x44332211
// EXPECT-CONTAINS: avx2 available:
#import "Basic";
#import "Bit_Operations";
#if CPU == .X64 { #import "Machine_X64"; }

add_five :: (x: int) -> int {
    result := x;
    #if CPU == .X64 {
        #asm { add result, 5; }
    } else {
        result += 5;
    }
    return result;
}

main :: () {
    print("add via #asm or fallback: %\n", add_five(10));
    v: u32 = 0xF0F0;
    print("popcount(0xF0F0): %\n", popcount(v));
    b: u32 = 0b1000;
    zero: u32 = 0;
    print("bit_scan_forward(0b1000): %, of 0: %\n", bit_scan_forward(b), bit_scan_forward(zero));
    h: u32 = 0x80;
    print("bit_scan_reverse(0x80): %\n", bit_scan_reverse(h));
    w: u32 = 0x11223344;
    print("byte_swap(0x11223344): 0x%\n", formatInt(byte_swap(w), base = 16));

    #if CPU == .X64 {
        info := get_cpu_info();
        print("avx2 available: %\n", check_feature(info.feature_leaves, .AVX2), to_standard_error = true);
    } else {
        print("avx2 available: not an x64 CPU\n", to_standard_error = true);
    }
}
