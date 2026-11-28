// Two ways to import: unqualified (all exported names land in this file's scope)
// and named (the module stays behind a namespace you choose).
// EXPECT: length = 5
// EXPECT: v = {3, 4, 0}
// EXPECT: max of 3 and 9 = 9

#import "Basic";            // unqualified: print, max, ... are usable directly
M :: #import "Math";        // named: everything from Math is M.something

main :: () {
    v := M.Vector3.{3, 4, 0};
    print("length = %\n", M.length(v));
    print("v = %\n", v);
    print("max of 3 and 9 = %\n", max(3, 9));
    // 'length(v)' without 'M.' would be "Undeclared identifier": the named
    // import adds only the name M to this scope.
}
