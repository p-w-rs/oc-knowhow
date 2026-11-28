// EXE: prog
// EXPECT-EXIT: 1
// EXPECT-CONTAINS: s32 sum so far: 2147483646
// EXPECT-CONTAINS: Arithmetic overflow. We tried to compute:
// EXPECT-CONTAINS: The operand type is s32, but the result does not fit into this type.
// A build file is a program that runs at compile time and creates the workspace for the real program.
// Build it with `jai build.jai`; it writes ./prog. Settings live in Build_Options (modules/Compiler).
// Here it turns on arithmetic overflow checking, which is OFF by default in every build mode
// (0.2.032), so the overflowing += in prog.jai stops the program instead of wrapping.
// set_build_options_dc(.{do_output = false}) keeps build.jai itself from becoming an executable;
// without it the compile fails with "No program entry point was found".
// Note: -quiet does not silence the workspace you create (its linker line and stats still print).
// Workspaces, message loops and plugins in depth: the jai-metaprogramming skill.

#import "Basic";
#import "Compiler";

#run {
    set_build_options_dc(.{do_output = false});

    w := compiler_create_workspace("prog");
    options := get_build_options(w);
    options.output_executable_name = "prog";
    options.arithmetic_overflow_check = .FATAL;    // OFF, NONFATAL or FATAL
    set_build_options(options, w);

    add_build_file("prog.jai", w);
}
