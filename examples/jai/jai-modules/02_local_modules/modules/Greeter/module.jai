// Folder module. Everything here is exported unless a scope directive says otherwise.
#load "style.jai";

greet :: (name: string) {
    greetings_so_far += 1;
    print("%", decorate(name));
    if greetings_so_far > 1  print(" (greeting #%)", greetings_so_far);
    print("\n");
}

#scope_module
// Visible to every file of this module, invisible to importers.
greetings_so_far := 0;

#import "Basic";   // the module needs its own imports; it cannot see the program's
