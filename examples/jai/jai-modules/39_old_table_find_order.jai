// Silent trap when updating older code: since 0.2.018 Hash_Table.table_find returns
// (found, value), success first. Code written for the old (value, found) order
// still compiles when the value type converts to and from bool context, and quietly
// swaps the meaning. Here the value lands in 'found' and the bool in 'value'.
// Also deprecated since 0.2.029: init(*table, n) (a zeroed table works; use
// table_resize to presize). table_reset now frees memory; the old behaviour is
// table_reset_keeping_memory. uninit was renamed deinit (0.1.050).
// EXPECT-COMPILE: Warning: This procedure is deprecated.
// EXPECT: old order: value=true found=7   <- swapped, no error
// EXPECT: if found: true (7 is truthy), so the bug hides until the value is 0
// EXPECT: old order on a zero value: found=0, reads as missing
// EXPECT: current order: found=true value=7
// EXPECT: allocated after table_resize: 128; table_reset_keeping_memory keeps 128; table_reset frees: 0

#import "Basic";
#import "Hash_Table";

main :: () {
    t: Table(string, int);
    init(*t, 16);                              // deprecated: compiles with a warning
    table_set(*t, "seven", 7);
    table_set(*t, "zero", 0);

    value, found := table_find(*t, "seven");   // OLD order
    print("old order: value=% found=%   <- swapped, no error\n", value, found);
    if found  print("if found: true (7 is truthy), so the bug hides until the value is 0\n");
    value, found = table_find(*t, "zero");
    print("old order on a zero value: found=%, reads as missing\n", found);

    ok, v := table_find(*t, "seven");          // CURRENT order
    print("current order: found=% value=%\n", ok, v);

    sizes: Table(int, int);
    table_resize(*sizes, 64);
    after_resize := sizes.allocated;
    for 1..10  table_add(*sizes, it, it);
    table_reset_keeping_memory(*sizes);
    kept := sizes.allocated;
    table_reset(*sizes);
    print("allocated after table_resize: %; table_reset_keeping_memory keeps %; table_reset frees: %\n", after_resize, kept, sizes.allocated);
    deinit(*t);
}
