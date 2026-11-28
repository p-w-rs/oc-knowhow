// A program with its own modules folder. The compiler searches ./modules (next to
// the first file you compile) before its own modules/, so no flags are needed.
//   modules/Greeter/module.jai   folder module: module.jai is its entry file
//   modules/Greeter/style.jai    loaded by module.jai with #load (same module)
//   modules/Shout.jai            single-file module
// EXPECT: Hello, Ada!
// EXPECT: Hello, Grace! (greeting #2)
// EXPECT: HEY

#import "Basic";
#import "Greeter";
#import "Shout";

main :: () {
    greet("Ada");
    greet("Grace");
    print("%\n", shout("hey"));
}
