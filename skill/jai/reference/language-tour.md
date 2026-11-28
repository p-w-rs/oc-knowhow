# Jai language tour (beta 0.2.032)

A complete reference of the core syntax in compact, tested form. Every snippet compiled and ran on 0.2.032; the
example number in brackets (`[ex 08]`) is a full runnable program in `examples/jai/jai/`. Metaprogramming in depth
(polymorphism, #insert, #modify, workspaces) is **jai-metaprogramming**; memory, threads and C interop are
**jai-systems**; library modules are **jai-modules**.

## 1. Files, entry point, imports

```
#import "Basic";              // module: modules/Basic/module.jai (sealed scope; imports its own deps)
#load "util.jai";             // another file of THIS program (shares the global scope)
Math :: #import "Math";       // named import: Math.sqrt(2.0)
main :: () { print("hi\n"); } // entry point: no parameters, no return value (use exit(n))
```
- Declarations at file scope may appear in any order; inside a procedure, declare local constants before use.
- `#scope_file` / `#scope_export` / `#scope_module` switch the visibility of the declarations that follow [ex 25].
- `#import,file "x.jai"`, `#import,dir "lib/M"`, `#import,string "code"`; module parameters
  `#import "M"(PARAM=true);`, program parameters `#import "Basic"()(ENABLE_ASSERT=false);`.
- Comments: `//` and nestable `/* … */`. Statements end with `;`; blocks use braces.

## 2. Declarations [ex 02]

| form | meaning |
|---|---|
| `x: int;` | variable, zero-initialized |
| `x := 3;` | variable, type inferred (s64) |
| `x: u8 = 3;` | typed variable |
| `X :: 3;` | compile-time constant (procedures, structs, enums, types are constants too) |
| `X : float64 : 2.5;` | typed constant |
| `buf: [4096] u8 = ---;` | explicitly uninitialized |
| `a, b := 1, 2;` / `x, y: int = 7;` | several at once (one value is copied to all) |
| `a, b = b, a;` / `x, y += 5;` | multiple assignment (right side evaluated first) / compound on each |
| `_, rem := divmod(17, 5);` | `_` discards a value |

## 3. Numbers, bools, literals [ex 03, 04, 05]

- Types: `s8 s16 s32 s64 u8 u16 u32 u64`, `int` (= s64), `float32` (= `float`), `float64`, `bool` (1 byte), `void`.
- Literals: `42`, `-7`, `0xFF`, `0b1010`, `1_000_000`, `1.5`, `2.0e3` (dot required), `0h7FC0_0000` (IEEE bits),
  `#char "A"` (65), `true`/`false`, `null`. Integer literals are s64, float literals float32 unless more digits are
  needed (then float64). A literal or `::` constant converts to any type that holds its value.
- Operators: `+ - * / %` (integer division and `%` truncate toward zero: `-7 / 2 = -3`, `-7 % 3 = -1`),
  `& | ^ ~ << >>` (shifts by ≥ the width give 0), rotations `<<<` `>>>`, comparisons, `&& || !`, compound
  assignments including `&&=` and `||=`. No `++`/`--`, no `?:`.
- Conversions: implicit only when lossless; else `cast(T) x`, `xx x`, `cast,no_check(T) x`, `cast,trunc(T) x`;
  `cast,force(B) a` between structs. Debug builds check narrowing casts at run time; constant casts at compile time.
- Truthiness (`if`, `while`, `ifx`): numbers ≠ 0, non-empty strings and arrays, non-null pointers, non-void Types;
  structs are not allowed.

## 4. Strings [ex 06, 07]

```
s := "Hello";                         // string = { count: s64; data: *u8 }; literal bytes are read-only
s.count; s[0];                        // 5, 72 (a u8)
tail := s; tail.data += 1; tail.count -= 1;   // "ello", no copy
if s == "Hello" {}                    // only == and != on strings
t := copy_string(s); t[0] = #char "J";       // mutable copy (free(t) later)
c := to_c_string(s); defer free(c);   // *u8 with a zero terminator
back := to_string(c);                 // view of a C string (no copy)
msg := tprint("% items", 3);          // temporary storage; sprint = heap
```
- Escapes: `\n \r \t \e \" \\ \0 \x41 \d065 \u00e9 \U0001F600`, and `\%` for a literal percent in print formats.
- Here-strings: `TEXT :: #string END` … a line starting with `END`; verbatim, ends with a newline;
  `#string,cr` uses CRLF; `#string,\% END` allows `\%` inside.
- Module String: `compare`, `equal`, `contains` (returns `found, remainder`), `begins_with`, `ends_with`,
  `find_index_from_left/right`, `split` (keeps empty fields), `join(a, b, …)` / `join(..arr, separator = ", ")`,
  `trim`, `replace`, `to_upper_copy`, `slice(s, start, count)`, `parse_int(*s)` … Basic has `to_integer`,
  `string_to_int`, `string_to_float_new` (success first), String_Builder (`append`, `print_to_builder`,
  `builder_to_string`).
- `for s` iterates bytes (`it` is a u8, `it_index` the byte offset); UTF-8 aware iteration: `for :utf8_iter s`
  (module Unicode).

## 5. Arrays [ex 08, 09]

```
fixed: [4] int;                       // 4 ints, zeroed; fixed.count == 4
view: [] int = fixed;                 // { count, data } pointing at fixed
dyn: [..] int;                        // { count, data, allocated, allocator }
array_add(*dyn, 1, 2, 3);             // pass the address
lit := int.[1, 2, 3];                 // [3] int
xs: [] int = [4, 5, 6];               // dot-less when the type is known (0.2.031); .[4, 5, 6] also works
grid: [3][2] float;                   // grid.count == 3, grid[0].count == 2
empty := int.[];                      // count 0, data null
```
- Fixed and resizable arrays convert to views implicitly; procedures usually take `[] T`.
- Basic: `array_add`, `array_find` (→ found, index), `array_insert_at`, `array_ordered_remove_by_index`,
  `array_unordered_remove_by_index`, `pop`, `peek`, `array_reserve`, `array_resize`, `array_reset` (frees),
  `array_reset_keeping_memory`, `array_free`, `array_copy`, `array_view`, `NewArray(n, T)`.
- Indices are bounds-checked in debug builds (constant indices on fixed arrays at compile time). `.data` pointers
  and views into a `[..]` become invalid when it grows.

## 6. Structs [ex 10, 11]

```
Vec2 :: struct { x, y: float; }
Entity :: struct {
    name  := "unnamed";               // default value
    pos:  Vec2;
    pos.y = 5;                        // default for a nested member
    #as using base: Base;             // members of Base reachable directly; Entity converts to Base
}
e := Entity.{name = "orc"};           // named members (others keep defaults)
v := Vec2.{1, 2};                     // positional: all members
w: Vec2 = {3, 4};                     // dot-less (0.2.022); .{3, 4} also works
return {};                            // all defaults, type from the return type
```
- Layout is declaration order with C-like padding; `size_of(T)`, `type_info(T).members[i].offset_in_bytes`.
  `b: u32 #align 1` changes a member's alignment; `} #no_padding` after the brace drops trailing padding.
- `using v;` in a block, `(using v: *V)` on a parameter, `using,only(x) q;`, `using,except(x) q;`.
- Structs may take parameters: `Stack :: struct (T: Type, N: int) { items: [N] T; }` → `Stack(int, 8)` [ex 23].
- Assignment copies the bytes. There are no constructors or destructors: write `init`/`deinit` procedures.

## 7. Enums [ex 12]

```
Shape :: enum u8 { CIRCLE; SQUARE :: 10; TRIANGLE; }   // 0, 10, 11; storage u8 (default s64)
Perm  :: enum_flags u8 { READ; WRITE; EXEC; }           // 1, 2, 4
Level :: enum u16 #specified { LOW :: 1; HIGH :: 2; }   // every value explicit
s := Shape.SQUARE;  t: Shape = .CIRCLE;                 // unary dot where the type is known
p := Perm.READ | .EXEC;  p &= ~.READ;
```
- `enum_names(E)`, `enum_values_as_s64(E)`, `enum_values_as_enum(E)`, `enum_range(E)`, `enum_highest_value(E)`;
  `print` shows names (`READ | EXEC` for flags); `cast(int) s` gives the number.
- `using Shape;` brings the names into scope. `#complete` on an `if e == {}` requires every member.

## 8. Unions [ex 19]

```
Bits :: union { f: float32; u: u32; }                  // all members at offset 0
Pixel :: struct { rgba: u32; #overlay (rgba) ch: [4] u8; }   // second view on an existing member
Kind :: enum u8 { NUMBER; TEXT; }
Value :: union kind: Kind { .NUMBER ,, n: int; .TEXT ,, s: string; }   // tagged (0.2.023+, bindings 0.2.025)
```
- Tagged unions print as `{TEXT, hello}`; there is no checked access yet: switch on `kind` yourself.
- Returning an untagged union from `#run` warns ("It is illegal to return an untagged union from compile-time
  execution, …"; to become an error); the bindings generator prefers `#overlay`.

## 9. Pointers [ex 13]

```
x := 5;
p := *x;          // *int: address of x
p.* = 6;          // write through p      (prefix form: (.*) p)
m: Monster; mp := *m; mp.hp = 10;      // members through a pointer: '.' (one level)
first := arr.data; (first + 2).*;      // pointer arithmetic in elements
ap := *arr; ap.*[1];                   // NOT ap[1] (that indexes like C)
q := New(Monster); defer free(q);      // heap object from context.allocator
```
- `*void` converts implicitly to and from other pointer types. `null` is false.
- A `*T` argument converts automatically to a `T` parameter (null → runtime check in debug builds); the reverse
  never happens.

## 10. Procedures [ex 14, 15]

```
divmod :: (a: int, b: int) -> quotient: int, remainder: int { return a / b, a % b; }
greet  :: (name: string, punct := "!", times := 1) { … }
sum    :: (xs: ..int) -> int { t := 0; for xs t += it; return t; }
apply  :: (f: (int) -> int, x: int) -> int { return f(x); }
q, r := divmod(17, 5);                 // q only: q := divmod(17, 5);
greet(times = 2, name = "Bob");        // named arguments in any order
sum(1, 2, 3); sum(..int.[4, 5]);       // varargs and spreading
apply(x => x + 1, 41);                 // lambda: a polymorphic procedure, captures nothing
```
- Return values with defaults: `-> a: int = 1, b := "x"`, then `return;` or `return 5;`.
- Overloading: declare the same name with different parameter types or counts.
- `inline` / `no_inline` on the declaration (`f :: inline (x: int) -> int {…}`) or at the call (`inline f(2)`).
- Parameters larger than 8 bytes (strings, structs, Any) are passed "maybe by reference" and are read-only in the
  callee (`Can't assign to an immutable argument.`); pass `*T` to modify.
- `loc := #caller_location` as a default parameter gives the caller's `Source_Code_Location`; `#location()` the
  current one.
- Calling conventions: `#c_call` (C ABI, no context), `#no_context`, `#foreign lib` for external functions with
  `lib :: #library "name";` / `#library,system "libc"` (C interop: **jai-systems**).
- Nested procedures can use outer constants, globals and other procedures, never outer locals (no closures).
- Operators: `operator + :: (a: V, b: V) -> V {…}`, `#symmetric`, `operator == …` (gives `!=`),
  `operator [] / []= / *[]` for indexing; one operand must be a struct.

## 11. Control flow [ex 16, 17, 18]

```
if x > 0 { … } else if x < 0 { … } else { … }
if x > 0 then print("pos\n"); else print("non-pos\n");      // `then` optional unless ambiguous
y := ifx x > 0 then 1 else -1;                              // expression if
z := ifx ok { a := 2; a * 3; } else { 0; };                 // block form: last expression is the value
while n < 10 { defer n += 1; … }                            // defer runs on every exit from the body
while line := next_line() { … }                             // named condition: `continue line;`
for 1..10 {}           for < 1..10 {}                       // inclusive; reverse visits 10..1
for item: items {}     for item, i: items {}     for * items { it.* += 1; }
for items { if bad(it) remove it; }                         // unordered remove ([..] and views)
for row: grid { for cell: row { if done break row; } }      // labeled by the iterator name
if key == { case "a"; … case "b"; …; #through; case; … }    // switch: no fallthrough without #through
if #complete shape == { case .CIRCLE; … case .SQUARE; … }
defer free(buffer);                                         // end of scope, reverse order
```
- `it` and `it_index` are the default names; `it` is a read-only copy of the element.
- `break`/`continue` take an iterator or condition name; `break` inside a `case` leaves the enclosing loop.
- Range ends that are variables are re-read every iteration; avoid unsigned `0..n-1` when n can be 0.
- `for` over custom containers uses `for_expansion` macros (jai-metaprogramming).

## 12. Types as values, Any, type_info [ex 20]

```
t: Type = float64;  if t == float64 {}            // types compare with ==
type_of(x); size_of(T); size_of(type_of(x));
info := type_info(Point);                         // *Type_Info_Struct: name, members (name, type, offset)
a: Any = n;                                       // { type: *Type_Info; value_pointer: *void }
if a.type.type == .INTEGER { v := (cast(*int) a.value_pointer).*; }
Handle :: #type,distinct u32;  Path :: #type,isa string;
```
- `print` and `..Any` parameters use this machinery. An `Any` points at the original value (no copy).

## 13. Context and memory [ex 21]

```
#add_context frame_index: int;                    // your own context field
c := context; c.frame_index = 7; push_context c { work(); }
s := sprint("…",, allocator = arena);             // ,, overrides context fields for one call
s := copy_string(x,, temp);                       // shorthand: the allocator
push_allocator(arena);                            // until the end of the scope (Basic macro)
reset_temporary_storage();                        // free all tprint/temp allocations (e.g. per frame)
```
- Allocators are `Allocator.{proc, data}` with `Allocator_Proc :: (mode, size, old_size, old_memory, data) ->
  *void` (modes in `Preload.jai`). Details and strategies: **jai-systems**.

## 14. Compile time [ex 24]

```
TABLE :: #run make_table();          // run at compile time, result is a constant
#assert size_of(Header) == 16;
#if OS == .LINUX { … } else { … }    // untaken branch must parse, is not type-checked
name := #ifx OS == .MACOS then "mac" else "other";
is_constant(expr);  #exists(NAME);   // queries
```
- `print` inside `#run` prints during compilation. `OS`, `CPU`, `IS_CROSS_COMPILING` are constants.
- Polymorphism: `(x: $T) -> T`, `(arr: [] $T)`, `($N: int)` value parameters, `Stack($T, $N)` struct parameters
  [ex 23]; restrictions, `#modify`, `#bake_arguments`, `#insert`, macros: **jai-metaprogramming**.

## 15. Printing [ex 22]

```
print("% + % = %\n", 2, 3, 5);       // % = next argument, any type
print("%2 before %1\n", "a", "b");   // numbered; %0 = next; %% = two adjacent args; \% = percent sign
print("%\n", formatInt(255, base = 16, minimum_digits = 4));   // 00ff
print("%\n", formatFloat(x, trailing_width = 2));
print("%\n", FormatInt.{value = 255, base = 16});              // struct-literal form
print("oops\n", to_standard_error = true);
log("info");  log_error("problem %", code);                    // stdout / stderr via context.logger
```
- Default formats live in `context.print_style` (e.g. `default_format_int.base = 16` in a pushed context).
- Structs print as `{1, 2.5, "pt"}` (short form up to 5 members), arrays as `[1, 2, 3]`, strings in arrays quoted,
  enums by name, pointers in hex grouped by 4 digits (`1_6b09_e840`), null as `null`, types by name.
