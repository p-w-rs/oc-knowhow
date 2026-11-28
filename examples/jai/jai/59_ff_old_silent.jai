// EXPECT-COMPILE: Warning: The '<<' syntax for a pointer dereference will soon be removed.
// EXPECT-COMPILE: Use of the for-loop directive "#v2" is now deprecated.
// EXPECT-COMPILE: Calling init() on a Hash_Table is no longer necessary
// EXPECT: 1. old downward range `for < 3..0`: 0 iterations; current `for < 0..3`: 3 2 1 0
// EXPECT: 2. old `value, found := table_find(...)`: value=true (bool) found=0 (s64) -> 'not found'
// EXPECT:    current `found, value := table_find(...)`: found=true value=0
// EXPECT: 3. old deref `<< p` still works (warning): 7; current p.* = 7, (.*) p = 7
// EXPECT: 4. trial cast syntaxes still compile: 2 2 2 (write cast(int) f)
// EXPECT: 5. #char "A" = 65, and a one-character string converts to u8: 65
// EXPECT: 6. dotted literals still work: {1, 2} [3, 4]; the old %0% hack: ab, now %%: ab
// EXPECT: 7. deprecated but working: #v2 loop ran 3 times, Hash_Table init() then count 1
// Old Jai that STILL compiles on 0.2.032, so nothing forces you to notice it. 1 and 2 are the dangerous
// ones: their meaning changed silently. Modernize all of them when you touch old code.
// 1. Reverse ranges: before 0.1.094 `for < hi..lo` counted down; now `<` reverses a normal lo..hi range,
//    so the old form runs zero times without any diagnostic. Write `for < i: 0..n-1`.
// 2. Hash_Table.table_find returns (found, value) since 0.2.018 (success first). Old code binding
//    (value, found) still compiles when the types happen to line up, e.g. Table(string, int).
// 3. Unary << warns on every use (0.2.022; removal announced). `jai prog.jai -no_dce +Rewrite` reports the
//    rewrite, `+Rewrite -write` applies it (back up first; -no_dce so dead code gets rewritten too).
// 4. cast(T, x) and x.(T) are leftovers of the 0.2.005 cast-syntax trial; the modules use cast(T) x.
// 5. #char still works; since 0.2.014 a one-character string literal converts to u8 directly.
// 6. .{...} and .[...] literals are still valid; the dot is optional when the type is known (0.2.022/0.2.031).
//    `%0%` was a workaround for the old meaning of %% (literal percent); now %% means two arguments.
// 7. #v2 (0.1.094 transition) and Hash_Table init() (0.2.029) only warn.

#import "Basic";
#import "Hash_Table";

V2 :: struct { x, y: int; }

main :: () {
    old_runs := 0;
    for < 3..0  old_runs += 1;
    print("1. old downward range `for < 3..0`: % iterations; current `for < 0..3`:", old_runs);
    for < 0..3  print(" %", it);
    print("\n");

    stock: Table(string, int);
    table_add(*stock, "apples", 0);
    value, found := table_find(*stock, "apples");        // OLD order: names swapped, types still fit
    print("2. old `value, found := table_find(...)`: value=% (%) found=% (%) -> '%'\n",
          value, type_of(value), found, type_of(found), ifx found then "found" else "not found");
    ok, count := table_find(*stock, "apples");
    print("   current `found, value := table_find(...)`: found=% value=%\n", ok, count);

    n := 7;
    p := *n;
    print("3. old deref `<< p` still works (warning): %; current p.* = %, (.*) p = %\n", << p, p.*, (.*) p);

    f: float = 2.75;
    print("4. trial cast syntaxes still compile: % % % (write cast(int) f)\n", cast(int) f, cast(int, f), f.(int));

    letter: u8 = "A";
    print("5. #char \"A\" = %, and a one-character string converts to u8: %\n", #char "A", letter);

    a: V2 = .{1, 2};
    b: [] int = .[3, 4];
    print("6. dotted literals still work: % %; the old \%0\% hack: %0%, now \%\%: %%\n", a, b, "a", "b", "a", "b");

    loops := 0;
    for #v2 i: 0..2  loops += 1;
    counts: Table(int, int);
    init(*counts, 16);
    table_add(*counts, 1, 1);
    print("7. deprecated but working: #v2 loop ran % times, Hash_Table init() then count %\n", loops, counts.count);
}
