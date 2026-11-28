// EXPECT: Hello, layout! (said by module Greeter, 2 greetings so far)
// EXPECT: util.jai was #load-ed: 3 squared is 9
// EXPECT: a file-scoped helper in util.jai: 10
// A small project without a build file:
//   main.jai                    entry file (holds main; `jai main.jai` builds ./main)
//   util.jai                    pulled in with #load: same program, same global scope, its own file scope
//   modules/Greeter/module.jai  a local module: a `modules` folder next to the entry file is searched
//                               automatically; any other folder needs `-import_dir <dir>` (relative to
//                               the entry file's directory)
// #import gives a module its own sealed scope (it cannot see this program's globals; it must import
// what it uses). #load is textual inclusion into the current program or module.
// Declarations after #scope_file are private to their file; #scope_export switches back.

#import "Basic";
#import "Greeter";
#load "util.jai";

main :: () {
    greet("layout");
    print("util.jai was #load-ed: 3 squared is %\n", square(3));
    print("a file-scoped helper in util.jai: %\n", uses_private_helper());
}
