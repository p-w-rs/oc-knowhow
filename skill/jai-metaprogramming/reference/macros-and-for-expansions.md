# Macros, for_expansion and `,,` in depth

Validated on Jai beta 0.2.032. Examples 20–22 and 24–28 in `examples/jai/jai-metaprogramming/`. Lessons: how_to/730
(for_expansion), 225 (`,,`), 497 (#caller_code), 600 (#insert with Code), 050 (#this in a Profile-style macro).

## What a macro is

`name :: (params) -> results #expand { ... }` is a procedure whose body is pasted into every call site after
typechecking the call. It is always inlined, fully typechecked, and hygienic.

| Inside the macro | Meaning |
|---|---|
| `x := 1;` | private to this expansion (the caller cannot see `x`) |
| `` `x := 1; `` | declares `x` in the caller's scope |
| `` `x += 1; `` | uses the caller's `x` (without the backtick: "Undeclared identifier 'x'.") |
| `` `defer stmt; `` | runs stmt when the caller's current block ends |
| `` `return v; `` | returns from the caller (its return types must match: "Too many return values" otherwise) |
| `return v;` | the macro's own result value |
| `#insert code_param;` | pastes a Code argument |
| `#procedure_name()`, `#this` | the caller's procedure (the macro is expanded into it) |

- Errors show the expansion chain: "Info: While expanding macro 'bump' here..." points at the call.
- A backtick outside a macro: "This declaration is backticked, but is not inside a macro."
- Arguments are evaluated once, before the body, like a procedure call (a side-effecting argument used twice ran
  once). Code parameters are not evaluated; they are pasted where you `#insert` them, as often as you insert them.
- Constant arguments stay constant inside the macro: `#caller_code` and `$args: ..Code` parameters can be used in
  `#run` and `#insert` inside the body (22).
- A backticked declaration goes into the caller's scope even if it is inside braces in the macro; generating
  `` { `i := 0; ... } `` several times redeclares `i` ("Redeclaration of 'i'."). Declare once, assign per copy (20).
- Passing Code: `timed(3, #code runs += 1);` or `#code { a(); b(); }`. A `;` before the closing parenthesis
  (`#code runs += 1;)`) is a parse error ("')' expected.").

## Patterns (all verified in 24)

```jai
scope_trace :: (name: string) #expand {          // enter/leave logging around the caller's block
    print("enter %\n", name);
    `defer print("leave %\n", name);
}
return_if :: (failed: bool, value: int) #expand { if failed `return value; }   // early exit helper
make_counter :: () #expand { `counter := 0; }                                    // inject a variable
timed :: (n: int, body: Code) #expand { for 1..n #insert body; }                 // run caller code n times
```
- Profiling macro: combine `#procedure_name()` or `#this` (the caller) with `` `defer `` to time the rest of the caller
  (how_to/050 shows a nested-depth version with `#add_context`).
- Constant expansion: `unroll :: ($count: int, body: Code) #expand { #insert -> string {...} }` generates count copies
  of the body (20).
- Expression text plus value: `check :: (cond: bool, call := #caller_code) #expand` prints the source of the failing
  condition (22). `show :: ($args: ..Code) #expand` labels each value with its expression (22); Print_Vars'
  `print_vars(...)` is the bundled version.

## Scope of inserted Code (verified in a probe)

| Inside a macro | Names in the Code resolve in |
|---|---|
| `#insert c` (c passed by the caller) | the scope where the `#code` was written: the caller's locals are visible |
| `#insert,scope() c` | the insertion point in the macro: macro locals are visible, caller locals are not |
| `#insert,scope(other_code) c` | the scope that `other_code` was written in (0.1.036) |
| generated strings / `compiler_get_code(root)` without a scope | the insertion point |

`compiler_get_code(root, original)` keeps the original's scope, which is what you want when rewriting a caller's
Code (21).

## Macro or procedure?

Use a procedure unless you need one of: the caller's variables or scope (backticks), `` `return `` / `` `defer `` in
the caller, Code arguments, the caller's syntax (`#caller_code`), or constants of the caller propagated into the
body. Every call pastes the body (code size, compile time), debugging steps through pasted code, and macros cannot
be stored in variables.

## for_expansion

```jai
for_expansion :: (r: *Ring, body: Code, flags: For_Flags) #expand {
    REVERSE    :: (flags & .REVERSE) != 0;
    BY_POINTER :: (flags & .POINTER) != 0;
    for <=REVERSE i: 0..r.count-1 {
        #if BY_POINTER  `it := *r.items[(r.head + i) % r.N];
        else            `it :=  r.items[(r.head + i) % r.N];
        `it_index := i;
        #insert body;
    }
}
```
- `for x: container` looks for a macro named `for_expansion` whose first parameter matches the container (by value
  or by pointer; the by-pointer form is found for values too). Without one: "Undeclared identifier
  'for_expansion'."
- The macro must declare `` `it `` and `` `it_index `` in the caller ("Undeclared identifier 'it'" otherwise) and
  `#insert body`. The user's names in `for v, i: c` are mapped onto them. `it_index` can be any type (a struct of
  coordinates, for example).
- Shortcut: `for `it, `it_index: inner_array { #insert body; }` backticks the loop variables directly.
- Flags: `.REVERSE` from `for <`, `.POINTER` from `for *`. They are constants inside the expansion, so use `#if`
  and the constant loop forms `for <=cond` and `for *=cond` (with a comma between them when both are given).
  Reject what you do not support at compile time: `#assert !(flags & .REVERSE) "…";` (27; error text
  "Compile-time assertion failed" plus "While expanding macro 'for_expansion' here...").
- Named iterators: any macro with the same signature, used as `for :name c`, e.g. `for :evens ring` (26). There is
  no renaming convention for extra backticked variables (the user must know their names).
- Loop control inside the user's body is rewritten with `#insert (...) body;`:
  - `break = break outer_label` makes `break` leave your outer loop (needed for nested loops, 26 Grid);
  - `continue = { ...; continue; }` customizes continue;
  - `remove = { ... }` implements `remove it` (swap-remove in a probe; Hash_Table, Bucket_Array and Xar implement
    it; Bit_Array uses `remove = #assert(false)` to forbid it).
- Bundled examples worth reading: Hash_Table (`for value, key: table`, supports remove), Bucket_Array, Bit_Array,
  Xar, Soa (iterates a struct-of-arrays by value, and by pointer via a temporary copy).
- Debugging: by default the debugger does not step into expansions; compile with `-debug_for` (or
  `Build_Options.debug_for_expansions = true`).

## Context changes with `,,`

```jai
#add_context depth: int;                           // a new field on the implicit context
say("nested",, depth = 2);                         // only for this call (and what it calls)
s := join("a", "b", "c", separator = "-",, temp);  // a bare Allocator means `allocator =`
log("value %\n", 7,, logger = quiet_logger);       // logger: (message: string, data: *void, info: Log_Info)
```
- `,,` is sugar for copying the context, changing fields, and `push_context` around the call; after the call the old
  values are back (28). The explicit form is `ctx := context; ctx.depth = 2; push_context ctx { ... }`.
- Any context field works: the base fields (`allocator`, `logger`, `logger_data`, `log_level`, `temporary_storage`,
  `assertion_failed`, ...; see `Context_Base` in modules/Runtime_Support.jai), fields that modules add with
  `#add_context` (Basic adds `print_style`), and your own. The context has a fixed maximum size
  (`Build_Options.context_size_max`, default 4096 bytes; `-context_size`).
- With metaprogramming this is how generated or library code is configured without new parameters.
- Types: the full context type is `#Context` (0.1.096; it can grow during compilation as modules add fields), e.g.
  `ctx: #Context = context;` or a parameter `c: *#Context`; a parameter of type `Context_Base` accepts `context` and
  sees only the base fields. Bare `Context` is gone ("Undeclared identifier 'Context'.", since 0.2.002; 41). Old code
  also passed allocators as named arguments (`copy_string(s, allocator = a)`); since 0.1.080 it is
  `copy_string(s,, allocator = a)`.

## Old macro and iteration code

| Old | Current |
|---|---|
| `#run_and_insert`, `#body_text` | `#insert #run f()`, `#insert -> string { ... }` |
| for_expansion with 4 parameters (2020) | `(container, body: Code, flags: For_Flags) #expand` (0.0.040) |
| `c: Context`, `push_context my_ctx { }` | `#Context`; `push_context { }` pushes a default context (0.2.001) |
| `f(x, allocator = a)` | `f(x,, allocator = a)` / `f(x,, a)` |
| `for < i: n..0` (downward range) | `for < i: 0..n` (since 0.1.094; the old form now runs ZERO times without a warning) |
