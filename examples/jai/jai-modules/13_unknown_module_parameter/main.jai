// Parameter names are checked; a typo is a compile error (so is a wrong type,
// passing parameters to a module without #module_parameters, and giving program
// parameters from inside a module or twice for the same module).
// EXPECT-COMPILE-ERROR: Argument name 'SIZ' (number 1) is not found in the module parameters.

#import "Pool_Of"(SIZ = 64);
main :: () {}
