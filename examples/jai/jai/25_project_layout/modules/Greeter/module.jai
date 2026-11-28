// A directory module: modules/Greeter/module.jai is what `#import "Greeter"` loads.
// Modules do not see the importing program, so they import their own dependencies.

#import "Basic";

greet :: (name: string) {
    greetings += 2;   // counts in twos just to show module state persisting between calls
    print("Hello, %! (said by module Greeter, % greeting% so far)\n", name, greetings, plural(greetings));
}

#scope_module   // visible to every file of this module, but not exported to importers

greetings := 0;

#scope_file     // visible only in this file

plural :: (n: int) -> string { return ifx n == 1 then "" else "s"; }
