// Module and program parameters. A `modules/` folder next to the first file is on the import path
// by default. Search order: -import_dir folders first, then that modules/, then the compiler's
// modules/ (more on module lookup and writing modules in the jai-modules skill).
//   #import "M"(A = 1)        module parameters
//   #import "M"()(P = true)   program parameters only (the empty () is required); allowed ONCE per
//                             program, even with identical values ("Cannot supply program
//                             parameters for the same module twice")
// Module imports are deduplicated only when their parameter lists are written identically:
// the same values in a different order give another copy. A plain #import "M" shares the copy
// that uses the default module parameters.
// Basic has program parameters too: #import "Basic"()(ENABLE_ASSERT = false) compiles asserts out.
// EXPECT: hello, Ada.
// EXPECT:   [Greeter(hello)] call #1
// EXPECT: HEY, Bob!!!
// EXPECT:   [Greeter(hey)] call #1
// EXPECT: hello, Cy.
// EXPECT:   [Greeter(hello)] call #2
// EXPECT: Shout and Again share a copy: true
// EXPECT: Shout and Swapped share a copy: false
// EXPECT: plain import shares the default copy: true

#import "Basic";
#import "Greeter"()(LOG_CALLS = true);                       // default module params; program param set once
Shout   :: #import "Greeter"(GREETING = "hey", LOUD = true);   // a second, separately compiled copy
Again   :: #import "Greeter"(GREETING = "hey", LOUD = true);   // identical list: deduplicated with Shout
Swapped :: #import "Greeter"(LOUD = true, GREETING = "hey");   // same values, other order: a third copy
Plain   :: #import "Greeter";                                  // default copy, same as the first import

main :: () {
    greet("Ada");
    Shout.greet("Bob");
    Plain.greet("Cy");
    print("Shout and Again share a copy: %\n", *Shout.calls == *Again.calls);
    print("Shout and Swapped share a copy: %\n", *Shout.calls == *Swapped.calls);
    print("plain import shares the default copy: %\n", *calls == *Plain.calls);
}
