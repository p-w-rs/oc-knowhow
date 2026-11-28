// Integer overflow is NOT checked by default, not even with -very_debug (0.2.032): s32 max + 1 wraps.
// Turn checks on per workspace with Build_Options.arithmetic_overflow_check = .FATAL (or .NONFATAL,
// which reports and continues). Code that overflows on purpose (hashes, RNGs) opts out with #no_aoc
// on a procedure, a block, or a for loop; #no_abc does the same for array bounds checks.
// EXE: checked
// EXPECT-EXIT: 1
// EXPECT-CONTAINS: fnv-1a hash with #no_aoc: 3840791239
// EXPECT-CONTAINS: wrapping block with #no_aoc: 0
// EXPECT-CONTAINS: Arithmetic overflow. We tried to compute:
// EXPECT-CONTAINS: 2147483647 + 1
// EXPECT-CONTAINS: The operand type is s32, but the result does not fit into this type.
#import "Basic";
#import "Compiler";

#run {
    set_build_options_dc(.{do_output = false});
    w := compiler_create_workspace("overflow checked");
    options := get_build_options(w);
    options.output_executable_name = "checked";
    options.text_output_flags = 0;
    options.arithmetic_overflow_check = .FATAL;
    set_build_options(options, w);
    add_build_file("main.jai", w);
}
