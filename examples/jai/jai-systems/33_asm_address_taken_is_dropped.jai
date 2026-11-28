// #asm pitfall on EVERY platform (0.2.032): an #asm operand must be able to live in a register.
// If the variable's address is taken anywhere in the procedure (passing it to print() does that:
// the argument becomes an Any that points at it), the compiler prints only an Info message and the
// instruction has no effect on the variable: no error, just a wrong result. On arm64 that Info even
// replaces the "does not support x64 asm" error (example 32), so unguarded #asm compiles to nothing.
// Fix: keep the asm operand register-only, copy the result into another variable before printing
// or taking its address, and guard x64 asm with #if CPU == .X64 (example 31).
// EXPECT-COMPILE: Info: This variable cannot be used as a register operand, because its address gets taken
// EXPECT: printed directly: 10 (the add was dropped)
// EXPECT: copied before printing: 15
#import "Basic";

direct :: () {
    x := 10;
    #asm { add x, 5; }               // x is also passed to print below: this add is lost
    print("printed directly: % (the add was dropped)\n", x);
}

copied :: () {
    y := 10;
    #if CPU == .X64 {
        #asm { add y, 5; }           // y never has its address taken: it stays in a register
    } else {
        y += 5;                      // portable fallback (arm64 has no #asm)
    }
    shown := y;                      // the copy is what print() points at
    print("copied before printing: %\n", shown);
}

main :: () {
    direct();
    copied();
}
