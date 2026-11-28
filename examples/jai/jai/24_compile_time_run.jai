// EXPECT-COMPILE: [compile time] building the table
// EXPECT: table baked at compile time: [0, 1, 4, 9, 16, 25, 36, 49]
// EXPECT: fib(20) computed by the compiler: 6765
// EXPECT: static if picked: little-endian 64-bit
// EXPECT: #ifx: macOS or Linux
// EXPECT: is_constant: true false
// `#run expr` executes code while compiling and turns the result into a constant (numbers, strings,
// arrays and plain structs). `#if` / `#ifx` choose code at compile time (the untaken branch must
// parse but is not type-checked). `#assert cond;` fails the build when cond is false.
// print() inside #run writes to the compiler's output, not the program's (see EXPECT-COMPILE above).
// The big picture (workspaces, #insert, #modify, the Compiler module) is the jai-metaprogramming skill.

#import "Basic";

squares :: () -> [8] int {
    print("[compile time] building the table\n");
    result: [8] int;
    for 0..7  result[it] = it * it;
    return result;
}

fib :: (n: int) -> int { if n < 2 return n; return fib(n - 1) + fib(n - 2); }

TABLE :: #run squares();
FIB20 :: #run fib(20);

#assert size_of(int) == 8;
#assert FIB20 == 6765;

main :: () {
    print("table baked at compile time: %\n", TABLE);
    print("fib(20) computed by the compiler: %\n", FIB20);

    #if CPU == .X64 || CPU == .ARM64 {
        print("static if picked: little-endian 64-bit\n");
    } else {
        print("static if picked: something else\n");
    }

    name := #ifx OS == .MACOS || OS == .LINUX then "macOS or Linux" else "other";
    print("#ifx: %\n", name);

    runtime := 3;
    print("is_constant: % %\n", is_constant(FIB20), is_constant(runtime));
}
