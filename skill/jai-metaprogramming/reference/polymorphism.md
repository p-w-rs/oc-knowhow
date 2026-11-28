# Polymorphism in depth ($T, bakes, #modify, restrictions, variants)

Validated on Jai beta 0.2.032. Examples 09–19 in `examples/jai/jai-metaprogramming/`. Lessons: how_to/100, 110,
115, 120, 160, 170, 180, 050 (#this).

## How a polymorphic call is solved

1. The compiler matches the call's argument types against the header, left to right, collecting `$` variables.
   Each variable is defined by exactly one `$` (a second `$T` is "Identifier '$T' is already declared as a
   polymorphic variable"); other mentions use it.
2. `#modify` (if any) runs with the solved variables and may change or reject them.
3. The header is instantiated with the final values; if an identical instance exists, it is reused (one copy per
   distinct set of variables in the whole program, unlike C++ per-translation-unit instantiation).
4. The body is compiled for that instance; #run/#assert inside it run then (once per instance).

Consequences:
- Solving uses only the call site and the header, never the body or the return type. `make :: () -> $T` cannot be
  called ("Compile-time variable 'T' is needed but was not specified") unless #modify or a bake fills T.
- Write the most specific pattern (`*[..] $T`, `[] $T`, `Holder($T, $N)`): errors then name the bad argument
  ("Type mismatch. Type wanted: s64; type given: string. ... in checking argument 2") instead of failing deep in the
  body ("Info: While generating a polymorph of this procedure").
- Put the `$` on the argument that is the "authority" (the container in `append(arr, item)`).

## Value parameters

| Syntax | Meaning | Caller must pass |
|---|---|---|
| `$n: int` | auto bake: n is a constant inside the body, one copy per value | a constant ("requires a value bake ... not a bakeable literal") |
| `$$n: int` | optional bake: constant callers get a baked copy, others one shared run-time copy | anything; test with `#if is_constant(n)` |
| `$x: $T` | both value and type baked | constant |
| `$args: ..Code` | macro taking expressions as Code (see code-nodes.md) | expressions |

- Inside the body a baked value can size arrays (`buf: [n] u8;`), drive `#if`, and be checked with `#assert`.
- Code bloat: every distinct baked value is another compiled copy. `$$` plus a small inline fast path is the usual
  compromise (10).
- Auto-bakes and polymorph variables live in the procedure's "constants" scope, so nested procedures and #run blocks
  inside the body can use them.

## Baking existing procedures

- `add_100 :: #bake_arguments add(b = 100);` creates a new procedure with that argument fixed (the value must be
  constant). It also fixes `$K: int`-style value parameters (`triple :: #bake_arguments scale(K = 3);`, 10) and works
  on structs (instantiation with some arguments given).
- `show_u8 :: #bake_constants show(T = u8);` fixes **type variables** (`$T`) by name, and only those: on a value
  parameter it fails with "There is no bakeable constant named 'K'. Did you mean #bake_arguments?" (41).
- `p :: #procedure_of_call f(args);` gives the exact procedure (overload and polymorph) a call would invoke, without
  calling it; compare two with `==` to check deduplication (09), assign it to a run-time variable, or take its
  type_of.

## Procedures as values

- A concrete procedure is a value (`f := square_int;`). A polymorphic one is not ("This declaration is polymorphic,
  thus it has no concrete representation, so it cannot exist in runtime code."), but it can be bound to a constant
  (`g :: square;`) and polymorphs when passed to a parameter of procedure type (`apply(square, 3)` with
  `f: (int) -> int`).
- Procedure types: `Callback :: #type (x: int) -> int;`. Quick procedures `x => x * 3` and `(a, b) => a + b` are
  polymorphic and infer their return type (the one exception to "no return type inference").

## Polymorphic structs

```jai
Small_Buffer :: struct (T: Type = float, Capacity: int = 8) {
    items: [Capacity] T;
    count: int;
    self: *#this;           // *Small_Buffer(T, Capacity) for this instance
}
push :: (b: *Small_Buffer, value: b.T) -> bool { ... }   // bare name: any instance
```
- Parameters are constants; `$` is optional; defaults and named arguments work (`Small_Buffer(Capacity = 4, T = int)`
  is the same type as `Small_Buffer(int, 4)`). `b: Small_Buffer;` alone uses all defaults; without defaults it is
  "Attempt to use polymorphic struct 'Box' as a value in an imperative scope".
- Parameters are readable as members of instances and of the type (`b.T`, `b.Capacity`).
- Reflection on instances (12): `type_info(Small_Buffer(int, 4))` has `specified_parameters` (T, Capacity; integer
  values are readable at `constant_storage.data + offset_into_constant_storage`), an empty `parameters`, and
  `polymorph_source_struct` pointing to the generic struct, whose `parameters` lists the unbound ones (0.2.012).
  `Type_Info_Struct.alignment` (0.2.030) is **-1 for polymorphic instances** in 0.2.032, compile time and run time,
  although the Preload comment promises at least 1 (plain structs report the real value, e.g. 8).
- A struct can also have `#modify` (validate or normalize parameters, 16) and `#insert` in its body (generate members
  from parameters, as modules/Soa.jai does).
- To keep code size down, split the struct into a non-polymorphic base (say `Buffer_Header` with the element Type
  and size stored as run-time values, embedded with `#as using`) and a thin polymorphic part on top; most procedures
  then take the base and compile once (how_to/120 discusses this).

## Type restrictions

| Pattern | Accepts | Notes |
|---|---|---|
| `x: $T/Entity` | Entity, or structs whose first `#as using` member chain leads to Entity | T is the real argument type; specialize with `#if T == Monster` |
| `x: $T/interface Has_Size` | any struct that has all members of Has_Size (names and types; order free) | Has_Size is just a member list; mismatch: "The given type does not match the required interface." |
| `x: $T/Holder` (polymorphic Holder) | any instance of Holder | mostly redundant with `x: Holder` |
| `x: $T/.[string, u8]` | exactly one of the listed types (a constant array of Types; 0.1.076) | overloads resolve through implicit conversions (0.2.021); String's `split` takes a separator this way. Other types: "Type mismatch: The type of this argument did not match any of the possible target types of a type restriction." (13) |
- A single-type target must be a struct: `$T/Filename` with a `#type,isa string` gives "Attempt to use a type
  restriction, but the target type is not a struct!", and passing an int to `$T/Shape` gives "... the source type is
  not a struct!". Use a type list for non-struct choices.
- `interface` became a reserved word in 0.2.017 (`interface := 3;` no longer parses).
- The bundle calls the `$T/X` syntax preliminary and plans a redesign; for anything beyond these cases use #modify.

## #modify

```jai
sum :: (values: [] $T) -> $R
#modify {
    info := cast(*Type_Info) T;
    if info.type == .INTEGER { R = ifx (cast(*Type_Info_Integer) info).signed then s64 else u64; return true; }
    if info.type == .FLOAT   { R = float64; return true; }
    return false, "sum() needs integers or floats";
}
{ ... }
```
- It is a hidden procedure `(variables...) -> (accept: bool, reason := "")` running at compile time after the match.
- Variables are mutable `Type` values, not constants: `x: T;` and `size_of(T)` fail ("When trying to evaluate a
  constant Type, a non-constant declaration was encountered"). Cast to `*Type_Info` and use `.runtime_size`, members,
  etc. Basic's `min`/`max`/`clamp` use a `#compile_time` helper (IsScalar) the same way.
- Changing a type variable works when arguments implicitly convert to the new type (widening ints, `#as` structs) or
  the caller writes `xx`. Collapsing types reduces the number of compiled copies (15: three element types, two copies).
- Rejection message: "#modify returned false: <reason>" plus "Info: While attempting a polymorph here." at the call.
- Two overloads may have identical headers when each has a #modify; the compiler picks the one whose #modify accepts
  (15 `encode`). This is the general way to overload on type properties.

## Type variants

| Declaration | Implicit conversions | Use |
|---|---|---|
| `Alias :: u32;` | identical type | a second name only |
| `Handle :: #type,distinct u32;` | only literals convert in; out needs `cast`/`xx` | ids, units that must not mix ("Type mismatch. Type wanted: Entity_Handle; type given: u32.") |
| `Meters :: #type,isa float;` | converts toward float (recursively up an isa chain), not between siblings | refinements that may use base procedures; calls returning the base type are re-tagged (0.1.053) |
- Type info: tag `.VARIANT`, `Type_Info_Variant.variant_of` points at the base, `variant_flags` DISTINCT or ISA.
- Overload resolution distinguishes isa variants (0.1.053); restrictions (`$T/Variant`) do not work with variants.
- `Type` values: a zero-initialized `Type` is `void` and tests false (0.2.029; "may change back" per the changelog),
  so `chosen: Type;` works as "no type yet" (17).

## Tagged unions (experimental)

`Shape :: union kind: Shape_Kind { .CIRCLE ,, radius: float; .RECT ,, size: [2] float; }` (tag declaration 0.2.023,
`.TAG ,, field` bindings 0.2.025). The tag is the first member and the payload members follow it; print shows
`{RECT, [3, 4]}`; a literal has two values `.{.RECT, value}` or none (one value is an error). There are no unwrap or
safety checks yet, the `,,` binding is described as a temporary syntax, and tagged unions cannot be returned from
#run (the payload is lost). For generic code, `Type_Info_Struct.textual_flags` has `UNION_IS_TAGGED` and
`tagged_union_bindings` maps each tag value to a member index (example 08 shows a generic "payload member for tag").
The pre-2025 `Tagged_Union` module was removed in 0.2.025.

## Other compile-time directives that show up in generic code

- `#symmetric` on a two-parameter procedure lets it match with the arguments swapped (`3 * money` and `money * 3`
  from one operator; without it: "Procedure call did not match any of the possible overloads").
- `#this` is the enclosing procedure, struct (polymorphic: the current instance) or scope as a constant; recursion in
  anonymous procedures (`x => { ... #this(x-1); }`), `*#this` members. Banned in headers and struct argument lists.
- `#procedure_name()` / `#procedure_name(p)` (0.1.030) constant name; `#location(x)` declaration site;
  `#caller_location` as a parameter default gives the call site (Source_Code_Location: fully_pathed_filename,
  line_number, character_number); `#file`, `#line`, `#filepath`.
- `#specified` on an enum: every member needs an explicit value (stable serialization; error "This declaration is
  inside an enum marked as #specified, but it does not provide an explicit value."). `#complete` on `if x == {}`
  over an enum requires all cases.
- `#deprecated "message"` on a procedure: callers get "Warning: This procedure is deprecated. Note: ..." (build
  succeeds).

## Compile cost

- Each distinct instance is compiled and kept; heavy generic code costs compile time. Measure with
  `compiler_begin_intercept(w, .DO_PERFORMANCE_REPORT_POLYMORPHS)`: the PERFORMANCE_REPORT message lists, per
  polymorphic procedure, `num_call_sites` and `distinct_polymorphs` (a probe of `twice(x: $T)` called with s64 twice,
  float and u8 reported 4 call sites, 3 polymorphs). `Build_Options.info_flags` (.POLYMORPH_MATCH,
  .POLYMORPH_DEDUPLICATE) enable more diagnostic output (not probed).
- `maximum_polymorph_depth` (default 100) stops runaway recursive polymorphs.
- Long generic headers may end with a trailing comma (allowed again since 0.2.025; 09).

## Reading older polymorphic code

| Old | Current |
|---|---|
| `#modify` that sets a variable to null to reject | `return false, "reason";` (since 0.1.015) |
| `#bake_constants f(K = 3)` for a value parameter | `#bake_arguments f(K = 3)` |
| `Intercept_Flags.DO_POLYMORPH_REPORT` / modules/Polymorph_Report | `.DO_PERFORMANCE_REPORT_POLYMORPHS` / modules/Performance_Report (0.1.069) |
| `Tagged_Union` module | `union kind: Kind { ... }` (0.2.025) |
| `using base: Base;` letting Derived pass as Base | `#as using base: Base;` (since 0.1.033). Without `#as`: `$T/Base` gives "Type restriction does not match. Type wanted: Base; type given: Derived." and a `Base` parameter gives "Type mismatch: incompatible structs" |
