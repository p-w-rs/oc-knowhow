// Hash_Table: Table(Key, Value) is an open-addressing table; a zero-initialized
// table is ready to use (no init call). Iterating gives it = value, it_index = key,
// in slot order (not insertion order). Struct keys need your own hash and compare
// procedures: Hash.get_hash only accepts integers, floats, bools, enums, pointers,
// strings and arrays.
// EXPECT: ada: found=true age=37
// EXPECT: alan after += 1: 42
// EXPECT: contains bob: false
// EXPECT: removed grace: true (was 85)
// EXPECT: find_or_add linus: newly added=true, starts at 0
// EXPECT: ada -> 37
// EXPECT: alan -> 42
// EXPECT: linus -> 56
// EXPECT: table_add does not check for duplicates: count=2, all values [1, 2]
// EXPECT: grid {1,2}=a {2,1}=b
// EXPECT: case-insensitive keys: true
// EXPECT: after 'remove it' in a loop: 2 entries, alan present: false
// EXPECT: values multiplied through 'for *': ada=370

#import "Basic";
#import "Hash_Table";
#import "Hash";
#import "Sort";
#import "String";

Point :: struct { x, y: int; }
point_hash :: (p: Point) -> u32 { return get_hash(p.x) ^ (get_hash(p.y) * 31); }
point_eq   :: (a: Point, b: Point) -> bool { return a.x == b.x && a.y == b.y; }

nocase_hash :: (s: string) -> u32 { return get_hash(to_lower_copy(s,, temp)); }
nocase_eq   :: (a: string, b: string) -> bool { return equal_nocase(a, b); }

main :: () {
    ages: Table(string, int);
    defer deinit(*ages);
    table_add(*ages, "ada", 36);
    table_add(*ages, "alan", 41);
    table_set(*ages, "grace", 85);
    table_set(*ages, "ada", 37);              // set = add or replace
    found, age := table_find(*ages, "ada");
    print("ada: found=% age=%\n", found, age);

    p := table_find_pointer(*ages, "alan");   // null if absent; edit in place
    if p  p.* += 1;
    print("alan after += 1: %\n", table_find_pointer(*ages, "alan").*);
    print("contains bob: %\n", table_contains(*ages, "bob"));
    removed, old := table_remove(*ages, "grace");
    print("removed grace: % (was %)\n", removed, old);
    slot, added := find_or_add(*ages, "linus");
    print("find_or_add linus: newly added=%, starts at %\n", added, slot.*);
    slot.* = 56;

    keys: [..] string;
    defer array_free(keys);
    for ages  array_add(*keys, it_index);     // it_index is the key
    quick_sort(keys, compare);                // sort for a stable printout
    for keys  print("% -> %\n", it, table_find_pointer(*ages, it).*);

    dup: Table(string, int);
    table_add(*dup, "k", 1);
    table_add(*dup, "k", 2);                  // a second entry, not a replacement
    print("table_add does not check for duplicates: count=%, all values %\n", dup.count, table_find_multiple(*dup, "k"));

    grid: Table(Point, string, point_hash, point_eq);
    table_set(*grid, .{1, 2}, "a");
    table_set(*grid, .{2, 1}, "b");
    print("grid {1,2}=% {2,1}=%\n", table_find_pointer(*grid, .{1, 2}).*, table_find_pointer(*grid, .{2, 1}).*);

    names: Table(string, int, nocase_hash, nocase_eq);
    table_set(*names, "Hello", 1);
    print("case-insensitive keys: %\n", table_contains(*names, "HELLO"));

    for ages  if it_index == "alan"  remove it;   // removal while iterating is supported
    print("after 'remove it' in a loop: % entries, alan present: %\n", ages.count, table_contains(*ages, "alan"));
    for * ages  it.* *= 10;                       // by pointer: it is *int
    print("values multiplied through 'for *': ada=%\n", table_find_pointer(*ages, "ada").*);
}
