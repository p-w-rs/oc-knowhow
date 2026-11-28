# Teaching and probing Jai (beta 0.2.032)

The user is learning Jai by experiment. An agent should explain a feature briefly, show a program that runs, and
then hand over experiments whose outcome the compiler decides. Everything below was tried on 0.2.032.

## 1. Explaining a feature

1. **Say what it is in two to four sentences**, in Jai's terms, and name the closest thing in a language the user
   knows (C, Odin) with the difference that matters. Example: "`for * arr` iterates by pointer: `it` becomes `*T`,
   so `it.* = 0` writes into the array. Plain `for arr` gives a read-only copy; Odin's `for &x in arr` is the
   equivalent."
2. **Show the smallest complete program** that demonstrates it (with `#import "Basic"` and `main`), and its real
   output. Prefer the examples in `examples/jai/jai/` (01–30 cover one idea each; 50–59 show wrong forms and their
   errors) or adapt one.
3. **Point to ground truth**: the how_to lesson (`~/jai/current/how_to/019_looping.jai`) and the module source
   (`grep -n "^array_add ::" ~/jai/current/modules/Basic/Array.jai`), or `library_search … sources=["jai-how-to"]`.
4. **Propose two or three experiments** (section 3), each with a prediction the user can check.
5. **Say what changed recently** if it did (dot-less literals, `p.*`, `%%`, `for <`), so old tutorials don't
   confuse them (false-friends.md §6–7).

## 2. A probe toolkit

| question | probe | notes |
|---|---|---|
| what type does this expression have? | `print("%\n", type_of(expr));` | literals: `1` s64, `1.5` float32, `#char "a"` s64 |
| how big / aligned / laid out? | `size_of(T)`, `type_info(T).alignment`, `for type_info(T).members print("% @ %\n", it.name, it.offset_in_bytes);` | `size_of` needs a Type |
| is it known at compile time? | `is_constant(expr)` | `::` is always constant, `:=` never |
| does a name exist here? | `#if #exists(NAME) {…}` | handy for version gates |
| what does the compiler think, without running? | a compile-time-only file (below) | 0.06 s, writes nothing |
| assert a property | `#assert size_of(Item) == 32;` | fails the build with the expression |
| where is it defined, what are the parameters? | `jails-query def file.jai name`, `sig file:line:col` | toolchain.md §9 |
| what code does it become? | `jai -output_ir f.jai`, read `.build/*_no_opt.ll` / `*.ll` | shows the hidden context pointer and out-pointer returns |
| debug vs release semantics | build the same file default and with `-o`, run both | checks disappear with `-o` (toolchain.md §7) |
| backend differences | `jai -x64 f.jai` vs `jai f.jai` (Linux) | results must match; x64 only on x86-64 |
| exact error text for a wrong form | compile it; for many forms at once use a bench (section 4) | quote the message, don't paraphrase |
| when did it change? | `library_search query="…" sources=["jai-changelog"]` or grep `CHANGELOG.txt` | then confirm with a probe |

Compile-time-only probe (keeps no executable, runs in about 0.06 s):

```
#import "Basic";
#import "Compiler";
Item :: struct { id: u8; price: float64; name: string; }
#run {
    print("type of 1 + 2.0: %\n", type_of(1 + 2.0));          // float32
    print("size % align %\n", size_of(Item), type_info(Item).alignment);   // 32 8
    for type_info(Item).members  print("  % @ %\n", it.name, it.offset_in_bytes);  // 0, 8, 16
    set_build_options_dc(.{do_output = false});
}
```

Run with `jai -quiet probe.jai`. Output from `print` inside `#run` appears during compilation (example 24 checks
it with an EXPECT-COMPILE header). Arithmetic in `#run` follows runtime rules (a u8 250 + 10 gives 4).

## 3. Experiments that teach (each verified)

Change one thing, predict, compile, read the message:

- **Pointers**: in example 13 replace `p.*` with `*p` → `Mismatching levels of indirection` (prefix `*` takes an
  address); replace `mp.hp` with `mp->hp` → `Semicolon expected after expression.`
- **Iteration**: in example 16 change `for * arr it.* += 1;` to `for arr it += 1;` → compiles, array unchanged; with
  a struct element type → `Can't assign to a large-value iterator…`. Try `for < 3..1` (nothing) vs `for < 1..3`.
- **Switch**: delete a case from a `#complete` switch (example 17) → `This 'if' was marked #complete...`; replace a
  case value with a variable → `Conditions listed by 'case' must be constant.`; remove `#through` and watch the
  output change.
- **Conversions**: assign an `s64` variable to an `s32` (`Loss of information…`), then the literal `10` (works),
  then a `::` constant (works); `cast(u8) 300` (compile error) vs a runtime value of 300 (runtime check, example 05)
  vs `-o` (silently 44).
- **Literals**: drop one value from a positional struct literal (`Not enough values provided…`); write `v :=
  {1, 2};` without a type (`…did not specify its type…`).
- **Scopes**: make a nested procedure use an outer local (`…(Closures are not supported.)`); move a `#scope_file`
  helper's caller into another file (example 25) → `Undeclared identifier` with a hint about `#scope_export`.
- **Context**: call `print` inside a `#c_call` procedure → `Cannot call into a native procedure…`; wrap it in
  `push_context {}`.
- **Build modes**: run example 05 normally (exit 1, cast message) and after `jai -o` (no check, prints a wrong
  value); overflow wraps silently until a build file enables `arithmetic_overflow_check` (example 26).
- **Formatting**: `print("%d\n", 5)` prints `5d`; `print("% %\n", 1)` is a compile error (Check plugin), and with
  `-no_check` a runtime message.
- **Old vs new**: compile `y := << p;` (warning) and run `+Rewrite`; try `for < 3..0` (old downward loop, zero
  iterations); `value, found := table_find(…)` (silently swapped, example 59).

## 4. Many wrong forms at once: workspace benches

A file stops at its first error, so "try these ten wrong spellings" needs ten compiles, unless each snippet gets its
own workspace. Pattern (examples 51, 52, 56, 58):

```
#import "Basic";
#import "Compiler";
SNIPPETS :: string.[ "main :: () { i := 0; i++; }", "main :: () { x := 1; p := &x; }" ];
#run {
    set_build_options_dc(.{do_output = false});
    for SNIPPETS {
        w := compiler_create_workspace(tprint("snippet %", it_index));
        o := get_build_options(w);
        o.output_type = .NO_OUTPUT;          // type-check only
        set_build_options(o, w);
        add_build_string(it, w);
    }
}
```

- Every workspace prints `In Workspace N ("snippet K"):` and its errors; the order varies between runs; exit 1.
- Snippets that need modules must import them inside the string (`"#import \"Basic\"; …"`).
- The Check plugin (print argument counts) is not attached to created workspaces; example 56 attaches it to one,
  and that one must come last (its error ends the metaprogram's `#run`).
- Turn a finished bench into an example with one `EXPECT-COMPILE-ERROR:` line per message.

## 5. Writing examples that test themselves

The runner (`pixi run jai-examples -- --skill jai`) reads header comments:
`// EXPECT: <stdout line>` (in order, exact), `// EXPECT-CONTAINS:` (stdout or stderr), `// EXPECT-COMPILE:`
(compiler output, e.g. `#run` prints or warnings), `// EXPECT-COMPILE-ERROR:` (must fail with that text),
`// EXPECT-EXIT: n`, `// RUN-ARGS:`, `// JAI-ARGS:`, `// EXE:`, `// PLATFORMS: linux`. Keep output deterministic:
no timings, addresses or hash-table order in EXPECT lines.

## 6. Habits that keep explanations right

- Run the code before claiming output. Version-stamp facts that may change ("(0.2.032)", "since 0.2.022").
- Quote compiler messages exactly (they are stable search keys); say which build mode a runtime behaviour needs.
- When material disagrees with the compiler, the compiler wins; when the how_to prose disagrees with its own code
  (019 on `for <`, 495 on `-plug`), the code wins.
- Prefer the bundle and current sources (`jai-how-to`, `jai-modules-src`, `jai-changelog`,
  `jai-encyclopedia-of-examples`, `jai-parser-source` tests) over talks, old blogs and the dated chapters of
  `the-way-to-jai`.
