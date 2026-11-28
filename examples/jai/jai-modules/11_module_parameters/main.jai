// #module_parameters (A := 1, ...) (P := 0, ...)
//   first list:  module parameters, chosen per #import; each distinct list is a
//                separate compilation of the module (own globals, own code)
//   second list: program parameters, set once by the main program, shared by every
//                import of that module anywhere in the program
// Instances are deduplicated only when the parameter lists are written identically.
// EXPECT: [counter] 1
// EXPECT: [counter] 2
// EXPECT: [by_two] 2
// EXPECT: [by_two] 4
// EXPECT: [by_two] 2
// EXPECT: default=2 By_Two=4 Reordered=2
// EXPECT: By_Two and Same_As_By_Two share state: true
// EXPECT: By_Two and Reordered share state: false
// EXPECT: [counter] 3
// EXPECT: Other_User got the default instance: true

#import "Basic";
#import "Counter"()(VERBOSE = true);                        // program parameter: () = keep module defaults
By_Two         :: #import "Counter"(STEP = 2, LABEL = "by_two");
Same_As_By_Two :: #import "Counter"(STEP = 2, LABEL = "by_two");   // identical text: same instance
Reordered      :: #import "Counter"(LABEL = "by_two", STEP = 2);   // same values, new instance!
#import "Other_User";                                        // imports Counter with no parameters

main :: () {
    bump(); bump();
    By_Two.bump();
    Same_As_By_Two.bump();
    Reordered.bump();
    print("default=% By_Two=% Reordered=%\n", count, By_Two.count, Reordered.count);
    print("By_Two and Same_As_By_Two share state: %\n", *By_Two.count == *Same_As_By_Two.count);
    print("By_Two and Reordered share state: %\n", *By_Two.count == *Reordered.count);
    print("Other_User got the default instance: %\n", bump_from_elsewhere() == 3);
}
