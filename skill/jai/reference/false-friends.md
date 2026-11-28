# False friends: habits from C, C++, Odin, Go and old Jai (beta 0.2.032)

Every row was compiled with beta 0.2.032 (macOS arm64; the benches also on two Linux x86-64 machines). Messages
are quoted exactly as the compiler prints them after `path:line,col: Error: ` so you can grep for them. Examples
50–59 in `examples/jai/jai/` reproduce all of them: 51 (C habits), 52 (Odin habits), 56 (language rules) and
58 (old Jai) are **benches** that compile each wrong snippet in its own workspace, so one `jai build.jai` shows
every error at once (a single file only ever reports its first error).

## How to use this page

- When the compiler rejects something that "obviously" works elsewhere, search this page for the message.
- When you review or port code, scan for the habits in the left columns, especially the **silent** ones (they
  compile and run, but do something else).
- When you see old Jai (talks, blogs, the community wiki, books written before 2025), use the last two sections.

## 1. Pointers and memory (C, C++, Rust, Odin)

| habit | Jai | error on 0.2.032 |
|---|---|---|
| `p := &x;` | `p := *x;` | `Expected an expression after '='.` |
| `y := *p;` (read through p) | `y := p.*;` or `y := (.*) p;` | prefix `*` takes the address: later `Mismatching levels of indirection. Type wanted: s64; type given: **s64` plus the note `Automatic dereferencing only travels one layer, from *T to T.` (ex. 50) |
| `p->field` | `p.field` (one level of pointer is dereferenced automatically) | `Semicolon expected after expression.` |
| Odin `^int`, `p^` | `*int`, `p.*` | `Unable to parse type instantiation.` |
| `NULL`, `nil`, `nullptr` | `null` | `Undeclared identifier 'NULL'.` (same for `nil`, `nullptr`) |
| `new(T)`, `make([]T, n)` (Go/Odin) | `New(T)`, `NewArray(n, T)` (Basic) | `Undeclared identifier 'new'.` / `'make'.` |
| `malloc`/`free` thinking: every object on the heap | values in structs and arrays; `New`/`free`, `defer free(p)` | — |
| `sizeof(x)` | `size_of(type_of(x))` or `size_of(T)` | `Undeclared identifier 'sizeof'.` |
| `size_of(x)` with a variable | `size_of(type_of(x))` | `Here we need a constant Type, but we got an expression of type 's32'.` |
| `ap[i]` on `ap: *[N]T` or `*string` | `ap.*[i]` | **silent**: C pointer indexing. `ap[0]` is the whole array (type `[N] T`), `ap[1]` the memory after it. No warning, although the 0.2.022 changelog announced one (ex. 57) |
| `p + 1` on `*T` | same: steps one element | — |
| writing through a `[]` view of a literal | copy first (`v := int.[1, 2, 3];` gives a local `[3] int`) | **runtime crash**: literals live in read-only memory (Mac: `SIGBUS ... invalid address alignment`; Linux: `SEGV_ACCERR ... write to read-only memory`) |

## 2. Declarations, types, conversions (C, C++, Go, Java)

| habit | Jai | error |
|---|---|---|
| `int x = 5;`, `auto x = 5;` | `x: int = 5;` / `x := 5;` | `Unable to parse an expression here. This looks like a C-style declaration (two identifiers in a row); maybe it's a mistake of habit? If you want to declare a variable, try "x: int;"` |
| `x := 5;` twice in a scope | `x = 6;` (assignment) | `Redeclaration of 'x'.` |
| `a = b = 0;`, `if (x = 5)` | `a, b = 0;` / `if x == 5` | `Operator '=' can only be used at statement level.` |
| implicit narrowing `s32 b = a64;` | `b: s32 = xx a;` (range-checked) or `cast(s32) a` | `Loss of information (trying to fit 64 bits into 32 bits). Can't do this without an explicit cast. Type wanted: s32; type given: s64.` (ex. 55) |
| mixing signed/unsigned `u8 + s8` | cast one side | `Type mismatch between the arguments of binary operator + (left type: u8; right type: s8).` |
| `float f = i;` | `f := cast(float) i;` | `Number mismatch. Type wanted: float32; type given: s64.` |
| `bool b = 1;` | `b := true;` | `Type mismatch. Type wanted: bool; type given: s64.` |
| `u32 all = -1;` | `0xFFFF_FFFF` or `cast,no_check(u32) -1` | `Number signedness mismatch. Type wanted: u32; type given: s64.` |
| `u8 a = 300;` | a value that fits, or `cast,trunc(u8) 300` | `Number signedness mismatch. Type wanted: u8; type given: s64.` (odd wording for a range error) |
| `cast(u8) 300` (constant) | `cast,trunc(u8) 300` if intended | `In a constant-expression cast, the bounds check failed. Number must be in [0, 255], but it was 300.` |
| `u8(x)`, `T(x)` (C++/Odin/Go) | `cast(u8) x`, `xx x` | `To instantiate a type with arguments, that type must be a struct.` |
| `'a'` | `#char "a"` or `"a"` where a u8 is expected | `Expected an expression after '='.` |
| `1e5` | `1.0e5` | `We parsed a declaration, so we expected a semicolon after it, but saw this instead.` |
| Odin `Meters :: distinct f64;` | `Meters :: #type,distinct float64;` | `We parsed a declaration, ...` |
| `struct #packed {…}` | member `b: u32 #align 1;` removes interior padding; `} #no_padding` after the brace removes trailing padding | `Expected '{' after 'struct'.` |
| `transmute(f32) x` | `#overlay` member or `(cast(*float32) *x).*` | `We parsed a declaration, ...` |

Verified struct layouts (size / alignment / member offsets): `{a: u8; b: u32;}` 8/4/0,4; with
`b: u32 #align 1` 5/1/0,1; `{a: u32; b: u8;} #no_padding` 5/4/0,4 (no trailing pad); `{a: u8; b: u32;}
#no_padding` stays 8/4/0,4 (no effect on interior padding).

## 3. Control flow and expressions

| habit | Jai | error |
|---|---|---|
| `i++`, `++i`, `i--` | `i += 1;` | `Error in unary expression.` |
| `cond ? a : b` | `ifx cond then a else b` | `We parsed a declaration, so we expected a semicolon after it, but saw this instead.` |
| `switch x { case 1: … }` | `if x == { case 1; … case; … }` | C-style declaration error (`try "x: switch;"`) |
| C fallthrough between cases | add `#through;` as the last statement of the case | — (cases never fall through) |
| `break;` to leave a `switch` | nothing; `break` inside a case leaves the enclosing **loop** | silent if you rely on C behaviour |
| `case y:` with a variable | constants only (enum members, literals, `::` constants) | `Conditions listed by 'case' must be constant.` |
| duplicate cases | one case per value | `Duplicate case.` |
| `for (i = 0; i < n; i++)` | `for i: 0..n-1` | `',' expected.` |
| Go `for i := 0; i < n; i += 1 {}` | `for i: 0..n-1 {}` | `Unable to parse a statement here.` |
| `for x in arr`, `for r in s` (Odin/Python) | `for x: arr`, `for arr` (`it`, `it_index`) | C-style declaration error (`try "arr: in;"`) |
| `for i in 0..<n` | `for i: 0..n-1` | `Expected an expression after '..'.` |
| `for x in arr { x = 0; }` (expecting to write back) | `for * arr { it.* = 0; }` | small types: **silent no-op**; structs/strings: `Can't assign to a large-value iterator. Perhaps you want to iterate by pointer, using 'for *'.` |
| `do { … } while (c);` | `while` + `defer` for the step | `Semicolon expected after expression.` |
| `if (struct_value)` | compare a member | `This expression cannot implicitly coerce to bool, even under the lax rules of an 'if' or 'while' condition. (Its type is T, which cannot implicitly coerce to bool).` |
| `z := .A;` | `z := E.A;` (unary dot needs a known enum type) | `This declaration is bound to a unary '.' dereference that was never resolved, so there is no way to know its type.` |
| `if c (x).* += 1;` without braces | `if c then (x).* += 1;` or braces | `Expected a statement before this semicolon.` (the paren continues the condition) |
| `for 0..n-1` with unsigned `n == 0` | use signed counts | **silent**: wraps to a huge range |
| changing the range end inside the loop | don't | **silent**: a variable end is re-read every iteration (the start is not) |
| `array_add` to the array being iterated | collect, then add | **silent**: new elements are visited; the data may move |

## 4. Procedures, strings, structs, operators

| habit | Jai | error |
|---|---|---|
| Odin `proc(a: int) -> int {}` | `(a: int) -> int {}` | `')' expected.` |
| `int main()` returning a status | `main :: () { …; exit(2); }` | `Entry point must not return a value.` |
| lambdas capturing locals (JS, C++ `[&]`, Rust) | pass a parameter or a struct; macros (`#expand` + `` `x``) can reach the caller's scope | `Attempt to use a variable from an outer stack frame. (Closures are not supported.)` (ex. 53) |
| modifying a by-value string/struct parameter | copy it (`t := s;`) or take a pointer | `Can't assign to an immutable argument.` |
| `"a" + "b"` | `join("a", "b")`, `tprint("%%", a, b)`, String_Builder | `Operator '+' does not work on strings. (Only == and != can be used on strings.)` (an `operator +` for strings is ignored: operators need a struct operand) |
| `s1 < s2` on strings | `compare(s1, s2) < 0` | `Operator '>' does not work on strings. (Only == and != can be used on strings.)` |
| `a == b` on structs | define `operator == :: (a: T, b: T) -> bool` (then `!=` works too) | `Procedure call did not match any of the possible overloads.` (lists Basic's S128/U128 overloads) (ex. 54) |
| positional literal with too few values | give all members, or name them `V.{y = 3}` | `Not enough values provided in this struct literal.` |
| untyped literal `v := .{1, 2};` | `v := V.{1, 2};` | `This declaration is bound to a struct or array literal that did not specify its type, so there is no way to know its type.` |
| `printf("%d %s", …)` | `print("% %", …)` | **silent**: prints `5d xs` |
| `printf`, `len(a)` | `print`, `a.count` | `Undeclared identifier 'printf'.` / `'len'.` |
| `print("% %", 1)` | match the count | `Incorrect number of arguments supplied to 'print': The format string requires 2 arguments, but 1 argument is given.` (Check plugin; only a warning for too many arguments; not checked in your own workspaces) |
| `#include "x.h"`, Odin `import "core:fmt"` | `#import "Basic"`, `#load "x.jai"` | `Invalid toplevel directive name 'include'` / `Semicolon expected after expression.` |
| Odin `package main` | nothing (files are `#load`ed or imported) | C-style declaration error (`try "main: package;"`) |
| Odin `when X {}` | `#if X {}` | `Semicolon expected after expression.` |
| Odin `[dynamic]T`, `append(&a, x)` | `[..] T`, `array_add(*a, x)` | `Undeclared identifier 'dynamic'.` / `Procedure call did not match any of the possible overloads.` (Basic's `append` is for String_Builder) |
| Odin `x := f() or_return` | `x, ok := f(); if !ok return …;` | `We parsed a declaration, ...` |
| `#c_call` callback calling Jai code | `push_context { … }` inside it | `Cannot call into a native procedure, from a #c_call procedure, without using push_context (because #c_call implies #no_context).` |
| `#must` on a return type | remove it | `Invalid directive in procedure header.` |
| local helper used before it is declared | declare local constants/procedures first | `Identifier 'K' is used before its declaration.` |
| `arr[7]` on `[4] int` | — | compile time: `Subscript is out of array bounds. (The attempted index is 7, but the highest valid index is 3.)` |
| writing to a `::` array | declare a variable copy | `Attempt to assign to a constant.` |

## 5. Jai vs Odin at a glance

| idea | Odin | Jai |
|---|---|---|
| procedure | `add :: proc(a, b: int) -> int {}` | `add :: (a: int, b: int) -> int {}` |
| package / imports | `package foo`, `import "core:fmt"` | no package line; `#import "Basic"`, `#load "x.jai"`, `M :: #import "M";` |
| print | `fmt.println(x)`, `fmt.printf("%v", x)` | `print("%\n", x)` |
| pointer type / address / deref | `^T`, `&x`, `p^` | `*T`, `*x`, `p.*` or `(.*) p` |
| dynamic array | `[dynamic]T`, `append(&a, x)`, `len(a)` | `[..] T`, `array_add(*a, x)`, `a.count` |
| slice | `[]T` | `[] T` (view: count + data) |
| loops | `for x in a`, `for &x in a`, `for i in 0..<n` | `for x: a`, `for * a`, `for i: 0..n-1` |
| switch | `switch x { case 1: }` (no fallthrough, `fallthrough`) | `if x == { case 1; }` (no fallthrough, `#through`) |
| ternary | `x if c else y` / `c ? a : b` | `ifx c then a else b` |
| errors | multiple returns + `or_return` / `or_else` | multiple returns + explicit checks (success first in new APIs) |
| distinct types | `distinct f64` | `#type,distinct float64` (also `#type,isa`) |
| compile-time if | `when` | `#if` / `#ifx` |
| implicit context | `context` (`proc "contextless"`) | `context` (`#no_context`, `#c_call`); change with `push_context` or `f(x,, allocator = a)` |
| defer | `defer x` | `defer x;` (same idea: scope exit, reverse order) |
| bit reinterpretation | `transmute(T)` | `#overlay` member or pointer cast + `.*` |
| packed struct | `#packed` | member `#align 1` / `} #no_padding` |
| bit sets | `bit_set[E]` | `enum_flags` |
| allocation | `new`, `make`, `delete` | `New`, `NewArray`, `free`, `array_free` |

## 6. Old Jai that no longer compiles (bench: example 58)

Each pair: old form → current form, the error, and when it changed (from `CHANGELOG.txt`).

| old | current | error on 0.2.032 | changed |
|---|---|---|---|
| `#place x; y: T;` | `#overlay (x) y: T;` | `The #place directive has been deprecated. It will no longer compile. Please use #overlay, or some other solution, instead.` | warning 0.2.021, error 0.2.027 |
| `#overlay a;` | `#overlay (a) b: T;` | `'(' expected.` | 0.2.020 syntax |
| `c: Context;` | `#Context` (or `Context_Base`) | `Undeclared identifier 'Context'.` | 0.2.002 |
| `New(T, initialized = false)` | `New(T, initialize = false)` (also NewArray) | `Argument name 'initialized' (number 2) is not found in the procedure being called.` | 0.2.032 |
| `f :: () -> void { return; }` | omit the return type | `Not enough return values: Wanted 1, got 0.` | 0.0.050 |
| `using base: Base;` passed as Base | `using #as base: Base;` (or `#as using`) | `Type mismatch: incompatible structs (wanted 'Base', given 'Derived').` | 0.1.033 |
| `byval(*s)` for `(s: S)` | `byval(s)` | `Mismatching levels of indirection. Type wanted: S; type given: *S` | 0.2.019 |
| `b: B = xx a;` (struct to struct) | `cast,force(B) a`, `xx,force a` | `Cannot cast from one struct to another without force modifiers. Type wanted: B (8 bytes); type given: A (8 bytes)` | 0.1.053 |
| `cast(E.loose) x` | `type_info(E).internal_type`, or a plain integer type | `'loose' is not a member of E.` | 0.2.022 |
| `copy_string(s, allocator = a)`, `New(T, a)` … | `copy_string(s,, a)`, `New(T,, allocator = a)` | `Too many arguments: Wanted 1, got 2.` | 0.1.080 |
| `make_vector2(1, 2)` | `Vector2.{1, 2}` / `{1, 2}` | `Too many arguments: Wanted 1, got 2.` | 0.2.002 |
| `#foreign_library "x"` | `#library "x"` | `Invalid toplevel directive name 'foreign_library'` | 0.2.002 |
| `#foreign_system_library "libc"` | `#library,system "libc"` | `Invalid toplevel directive name 'foreign_system_library'` | 0.2.002 |
| `#run_and_insert` | `#insert #run f()` / `#insert -> string {…}` | `Invalid toplevel directive name 'run_and_insert'` | long ago |
| `cast(*T).* p` | `(cast(*T) p).*` | `cast(T).* was a temporary experiment from a disfavored syntax. It's no longer supported. Sorry for the inconvenience!` | 0.2.022 |
| `cast.*(*T) p` | same | `'(' expected.` | 0.2.022 |
| `#ifx c then a; else b;` | `#ifx c then a else b` | `'else' without 'if'.` | 0.1.084 |
| local constant used before declaration | declare first | `Identifier 'K' is used before its declaration.` | 0.1.065 |
| `*Thing.{1}` | `v := Thing.{1}; p := *v;` | `Attempt to create a struct literal, but the left-hand type is not a struct.` | — |
| `p.?field` | explicit null check | `Unable to parse an expression to the right of this binary operator.` | 0.2.009 |
| `{:int: 1, 2}` | `int.[1, 2]` / `[1, 2]` | `'}' expected.` | 0.0.078 |
| relative pointers `*~s16 T` | module Relative_Pointers | `We parsed a declaration, ...` | 0.1.059 |
| `#import "Tagged_Union"` | `union kind: Enum { .A ,, a: T; }` | `Unable to find a module called 'Tagged_Union' in any of the module search directories.` | 0.2.025 |
| `__temporary_allocator` | `temp` | `Undeclared identifier '__temporary_allocator'.` | 0.2.029 |
| `get_time()` | `seconds_since_init()` | `Undeclared identifier 'get_time'.` | 0.2.002 |
| `get_system_time()`, `System_Time` | `current_time_consensus()`, `to_calendar()` | `Undeclared identifier 'get_system_time'.` | 0.2.002 |
| `Swap(*a, *b)` | `swap(*a, *b)` or `a, b = b, a;` | `Undeclared identifier 'Swap'.` | 0.2.022 |
| `table_find_new` | `table_find` (success first) | `Undeclared identifier 'table_find_new'.` | 0.2.022 |
| `bubble_sort` | `quick_sort` (module Sort) | `Undeclared identifier 'bubble_sort'.` | 0.2.022 |
| `running_at_compile_time()` | `#compile_time` | `Undeclared identifier 'running_at_compile_time'.` | 0.1.043 |
| `concatenate(a, b)` | `join(a, b)` | `Undeclared identifier 'concatenate'.` | 0.1.028 |
| `uninit(*table)` | `deinit(*table)` | `Undeclared identifier 'uninit'.` | 0.1.050 |
| `Initialize(*x, T)` | `Initialize(*x)` | `Too many arguments: Wanted 1, got 2.` | 0.1.071 |
| `enum_values(E)` | `enum_values_as_s64(E)` / `enum_values_as_enum(E)` | `Undeclared identifier 'enum_values'.` | 0.1.028 |
| `print("100%%")` | `print("100\%")` | `Incorrect number of arguments supplied to 'print': The format string requires 2 arguments, but 0 arguments are given.` | meaning changed 0.2.022 |
| `jai f.jai -plug Iprof` | `jai f.jai +Iprof` | `Unknown argument '-plug'.` | 0.2.012 |
| `jai f.jai -- args` | `jai f.jai - args` | `Unknown developer option 'alpha'. Use '-- help' for help. Any command-line option after the last -- is reserved for the compiler.` | 0.1.043–0.1.048 |
| `jai -release f.jai` | `jai -o f.jai` (`-od` keeps stack traces) | warning `*** Warning: -release will go away, ...` | 0.2.026 |

## 7. Old Jai that still compiles (example 59)

| old | what happens on 0.2.032 | modernize to |
|---|---|---|
| `for < 10..0` (count down) | **runs zero times, no diagnostic** (since 0.1.094, `<` reverses a normal low..high range) | `for < 0..10` |
| `value, found := table_find(*t, key)` | **silent swap** when the types fit (e.g. `Table(string, int)`: `value` gets the bool, `found` the int; `if found` is false for a value of 0). Success-first since 0.2.018 | `found, value := table_find(*t, key)` |
| `<< p` | warning on every use: `The '<<' syntax for a pointer dereference will soon be removed. Instead, please use .* as postfix, or (.*) as prefix.` | `p.*`; batch: `jai f.jai -no_dce +Rewrite` (report), `+Rewrite -write` (rewrite; back up first) |
| `for #v2 < 0..n` | warning `Use of the for-loop directive "#v2" is now deprecated. ...` | `for < 0..n` |
| Hash_Table `init(*t, n)` | warning `This procedure is deprecated. Note: "Calling init() on a Hash_Table is no longer necessary (a default-initialized table is all you need)."` | drop it, or `table_resize(*t, n)` |
| `cast(T, x)`, `x.(T)` | compile silently (0.2.005 experiment) | `cast(T) x` |
| `#char "x"` | fine | also `"x"` where a u8 is expected (0.2.014) |
| `.{a, b}`, `.[a, b]` | fine | `{a, b}`, `[a, b]` when the type is known (0.2.022 / 0.2.031) |
| `"%0%"` (old workaround for `%%`) | still prints two arguments | `"%%"` |
| `-release`, `-release_debug` | warning, still builds | `-o`, `-od` |
| Hash_Table `table_reset` | now frees memory (0.2.029) | `table_reset_keeping_memory` for the old behaviour |
| String `contains(s, x)` | returns `(found, remainder)` (0.1.096); the extra value may be ignored | — |
| `split(s, sep)` | allocates with `context.allocator` (not temp) since 0.1.080 | `split(s, sep,, temp)` |

Where old material is most likely: Jonathan Blow's 2014–2020 talks (historical), the community wiki
(`jai-community-wiki`, dated: `#place`, bare `Context`), the-way-to-jai chapters 9+ and its Appendix C (`#must`,
`#place`, `<<`, `allocator =`), Forrest Smith's 2023 post (`jai-blog-forrest-aoc`), tsoding's jaibreak
(`jaibreak-source`: `Tagged_Union`, old `table_find`, `Swap`), and every third-party repo not yet updated for the
0.2.032 `initialized` → `initialize` rename.
