// modules/Config.jai and modules/Config/module.jai in the same search folder:
// the compiler refuses to guess. Delete one of them.
// EXPECT-COMPILE-ERROR: This module exists in both single-file and directory form

#import "Config";
main :: () {}
