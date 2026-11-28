// A module can deliberately re-export: 'using Name :: #import' exports both the
// namespace and its contents; an alias constant exports a single name.
// EXPECT: [toolkit] ready
// EXPECT: print came through Toolkit: 42
// EXPECT: Basic.sprint works too: x=7
// EXPECT: say is an alias of print

#import "Toolkit";   // the only import in this file

main :: () {
    toolkit_hello();
    print("print came through Toolkit: %\n", 42);
    print("%\n", Basic.sprint("Basic.sprint works too: x=%", 7));
    say("say is an alias of %\n", "print");
}
