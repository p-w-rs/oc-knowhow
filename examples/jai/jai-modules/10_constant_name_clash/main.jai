// Two unqualified imports that both export a non-procedure name (a constant, a
// type, a global) collide as soon as both are imported, even if you never use it.
// The fix is a named import for at least one of them: Old :: #import "Old_Format";
// EXPECT-COMPILE-ERROR: Redeclaration of 'VERSION'

#import "Basic";
#import "Old_Format";
#import "New_Format";

main :: () { print("%\n", encode(1)); }
