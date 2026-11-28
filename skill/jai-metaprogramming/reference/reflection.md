# Reflection in depth (type_info, Type_Info_* structs, notes, Any, serializers)

Validated on Jai beta 0.2.032. Examples 08, 12, 17, 29–32 in `examples/jai/jai-metaprogramming/`. Lessons:
how_to/020 (type_info), 030 (Any), 935 (type-info reduction). The structs are declared in `modules/Preload.jai`
(`library_search query="Type_Info_Struct_Member" sources=["jai-modules-src"]`); helpers live in Basic,
modules/Reflection and modules/Compiler.

## What type_info gives you

`type_info(T)` is a compile-time constant pointer to the most specific struct for T (`type_of(type_info(Player))`
is `*Type_Info_Struct`). `cast(*Type_Info) T` does the same for a `Type` value that is not constant (inside
`#modify`, in loops over types). Every Type_Info starts with:

- `type: Type_Info_Tag`: INTEGER, FLOAT, BOOL, STRING, POINTER, PROCEDURE, VOID, STRUCT, ARRAY, OVERLOAD_SET, ANY, ENUM,
  POLYMORPHIC_VARIABLE, TYPE, CODE, UNTYPED_LITERAL, UNTYPED_ENUM, VARIANT;
- `runtime_size` (-1 for polymorphic types and for structs whose compilation has not finished).

| Tag | Struct | Fields |
|---|---|---|
| INTEGER | Type_Info_Integer | `signed` |
| POINTER | Type_Info_Pointer | `pointer_to` |
| PROCEDURE | Type_Info_Procedure | `argument_types`, `return_types`, `procedure_flags` (IS_POLYMORPHIC, HAS_NO_CONTEXT, IS_C_CALL, IS_SYMMETRIC, ...) |
| STRUCT | Type_Info_Struct | `name`, `members`, `notes`, `parameters`, `specified_parameters`, `polymorph_source_struct`, `tagged_union_bindings`, `status_flags`, `nontextual_flags`, `textual_flags`, `alignment`, `initializer`, `constant_storage` |
| ARRAY | Type_Info_Array | `element_type`, `array_type` (FIXED, VIEW, RESIZABLE), `array_count` (-1 unless FIXED) |
| ENUM | Type_Info_Enum | `name`, `internal_type` (*Type_Info_Integer), `names`, `values` ([] s64), `enum_type_flags` (FLAGS, COMPLETE, SPECIFIED) |
| VARIANT | Type_Info_Variant | `name`, `variant_of`, `variant_flags` (DISTINCT, ISA) |
| FLOAT, BOOL, STRING, VOID, ANY, TYPE, CODE | Type_Info | no extra fields |

`Type_Info_Struct_Member`: `name`, `type`, `offset_in_bytes`, `flags` (CONSTANT, IMPORTED, USING, AS, OVERLAY,
PROCEDURE_WITH_VOID_POINTER_TYPE_INFO), `notes`, `offset_into_constant_storage` (-1 unless stored there).

Verified details:
- Struct constants (`MAX_HP :: 200;`) appear in `members` with flag CONSTANT and offset -1 (29); skip them when
  walking data.
- `#as using base: Body;` is ONE member (flags USING | AS); its fields are not repeated in `members`. Basic's
  `get_field(info, "y")` searches through USING members and returns the member plus its total offset.
- `textual_flags` carries FOREIGN, UNION, NO_PADDING, TYPE_INFO_NONE, ..., UNION_IS_TAGGED (08).
- `alignment` (0.2.030): 8 for `struct { a: u8; b: float64; }`, but -1 for instances of polymorphic structs in 0.2.032
  (12).
- Polymorphic struct instances: `specified_parameters` names the parameters given (values in `constant_storage` at
  `offset_into_constant_storage`), `parameters` is empty, and `polymorph_source_struct.parameters` lists the generic
  ones (0.2.012, 12).
- Tagged unions: the tag is member 0; `tagged_union_bindings` maps `constant_value` (the tag value) to `member_index`
  (0.2.025, 08).
- A zero `Type` value is `void` (and false in conditions) since 0.2.029 (17).

## Notes

- Syntax: after a member's semicolon (`name: string; @Key`), after a procedure body (`f :: () {...} @Command`), after
  `struct`/`enum` (`Player :: struct @Saveable {`); several in a row; `@"text with spaces"` (0.0.098). Notes are
  plain strings: parse arguments yourself (`jaison-source` reads `@JsonName(new_name)` by splitting the text).
- Run time and #run: `Type_Info_Struct.notes`, `Type_Info_Struct_Member.notes` ([] string) (29, 30).
- Metaprograms: `Code_Procedure_Header.notes`, `Code_Struct.notes`, `Code_Declaration.notes` ([] *Code_Note with
  `.text`) (34, 35, 39, 40). `compiler_begin_intercept(w, .SKIP_EXPRESSIONS_WITHOUT_NOTES)` delivers only noted items.
- Notes on a polymorphic procedure are copied to its polymorphs (since 0.1.079).

## Enums

- Basic: `enum_names(T)`, `enum_values_as_s64(T)`, `enum_values_as_enum(T)` (temporary array; may be renamed
  `enum_values` later), `enum_highest_value(T)`, `enum_range(T)`. modules/Reflection: `enum_name_to_value(T, "NAME")
  -> value, ok`, `enum_value_to_name(v)`, `get_enum_value(*data, info)`, `set_enum_value`.
- `print` shows enum names and `enum_flags` combinations (`READ | EXEC`).
- Values continue from the last explicit one (`CALM :: 1; ANGRY :: 5; SLEEPY;` gives 6); `#specified` forbids implicit
  values, which keeps serialized numbers stable.
- Old names: `enum_values(T)` → `enum_values_as_s64`/`_as_enum`; `get_enum_name` → `enum_value_to_name`; the implicit
  `E.loose` member was removed in 0.2.022 (use `type_info(E).internal_type`).

## Any

`Any` holds `type: *Type_Info` and `value_pointer: *void`; every argument of `print` is passed as one. Switch on
`a.type.type`, cast `value_pointer` to the right pointer type, and remember that an Any points at the original value
(don't keep it past the value's lifetime). Assigning an Any to an Any copies it instead of boxing it (how_to/030).
`Any_Struct` in Preload is the struct form (old code called it `Preload.Any`).

## Walking data at run time (30)

One procedure, `write_json(sb, data: *void, info: *Type_Info)`, handles every type: switch on `info.type`; for
STRUCT loop over `members` at `data + offset_in_bytes`; for ARRAY use modules/Reflection's
`get_array_count_and_data(data, info)` (works for fixed, view and resizable arrays); for ENUM use `get_enum_value`
and the names table; skip CONSTANT members and members with an `@NoSave` note. It works on types the code never saw,
including through `Any`, but re-walks the type on every call. `jaison-source` is a complete, maintained version
(typed JSON in both directions, `@JsonIgnore`, `@JsonName(...)`).

## Generating code from type info (31)

Inside a polymorphic procedure, `type_info(T)` is constant, so `#insert -> string { ... }` can write one statement per
member. Each struct type gets its own generated body, recursion works through the same polymorphic procedure, and the
generated text is in `.build/.added_strings_w2.jai`. No type walk happens at run time. modules/Soa does the same to
turn a struct into a struct of arrays.

## Type information in metaprograms

- `get_type_table()` (Compiler) lists every Type_Info of the current workspace at compile time; with
  `is_subclass_of(info, "Base")` it finds all structs that `#as using` Base (verified). how_to/470 builds an entity
  registry this way from inside the target program.
- In messages, `Code_Struct.defined_type` is the *Type_Info_Struct and every typechecked node has `.type`.
- `compiler_set_type_info_flags(T, .NO_TYPE_INFO | .PROCEDURES_ARE_VOID_POINTERS | .NO_SIZE_COMPLAINT)` from a #run
  or metaprogram changes types you cannot edit (32).

## Keeping type info small (32)

Only types that the program asks about with `type_info`, `print` or `Any` (and what they reference) are emitted.
For huge structs (for example procedure tables of a graphics API) use:
- `struct #type_info_none`: no members recorded (print shows `{}`);
- `struct #type_info_procedures_are_void_pointers`: procedure members are described as `*void` (their real types
  stay intact for code);
- `struct #type_info_no_size_complaint`: silence the size warning;
- the same flags through `compiler_set_type_info_flags` (they can only be added, not removed).
