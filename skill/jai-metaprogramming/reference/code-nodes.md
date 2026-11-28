# Code as data in depth (#code, #insert, syntax-tree nodes)

Validated on Jai beta 0.2.032. Examples 20–23, 31, 34–36 and 39 in `examples/jai/jai-metaprogramming/`. Lessons:
how_to/600 (#insert), 630 (compiler_get_nodes), 497 (#caller_code). The node structs are declared in
`modules/Compiler/Compiler.jai` (`library_search query="Code_Procedure_Call" sources=["jai-modules-src"]`); read
the struct before touching a field, since the layout changes between betas.

## Code values

| Form | Meaning |
|---|---|
| `#code expr` / `#code { statements }` | a Code constant: parsed syntax plus the scope it was written in; not typechecked |
| `#code,typed expr` | typechecked where written (0.1.002); `get_root_type(c)` then returns SUCCESS and the type |
| `#code,null` | a null Code (tests false: `if c`); use it as a default for optional Code parameters |
| `code_of(expr)` | the Code of an expression, after constant substitution (0.1.001) |
| `call := #caller_code` | as a macro parameter default: the Code of the call that expanded the macro (0.0.080) |
| `$args: ..Code` | macro parameter: any number of expressions, each a constant Code (as in modules/Print_Vars) |

- Plain `#code` has no types: `get_root_type` reports NOT_TYPED. The only modifiers are `null` and `typed`
  (`#code,infer`, suggested by a comment in Compiler.jai, gives "Invalid modifier 'infer' on #code. The only valid
  modifiers are 'null' and 'typed'.").
- Code passed to a macro arrives with constants substituted: `fixed_array.count` and `LIMIT * 2` come back as numbers
  (22). If you need the spelling the user wrote, don't pass constants.
- Code is a compile-time value: you can store it in constants, pass it to macros and `$` parameters, and use it in
  `#run`, but not at run time.

## #insert

| Form | Where | Notes |
|---|---|---|
| `#insert "x *= 2;"` | statement level, struct and enum bodies, file scope | string must be constant; may contain several statements |
| `y := #insert "x + 1;";` | expression level | exactly one expression, still terminated by `;` |
| `#insert c` (Code) | statement or expression | names resolve in the scope where the Code was written |
| `#insert,scope() c` | inside macros | names resolve at the insertion point (0.1.036) |
| `#insert,scope(other) c` | anywhere | names resolve where `other` (a constant Code) was written |
| `#insert #run f()` | anywhere | f returns a string or a Code |
| `#insert -> string { ... }` / `#insert -> Code { ... }` | anywhere | short form of `#insert #run () -> string { ... }();` |
| `#insert (break = break outer, continue = {...}, remove = {...}) body` | for_expansion macros | rewrites loop control inside the pasted body |

- Generated strings are written to `.build/.added_strings_w<N>.jai` (N = workspace number) with a comment naming the
  file and line that generated them. Errors point into that file, so read it when generated code fails.
  `Build_Options.write_added_strings` (default true) controls it.
- A literal `%` in a print format is `\%` inside an ordinary string literal (0.1.077). Here-strings are raw: in
  `#string END ... END` a `\%` stays a backslash plus a format slot, and Check does not catch it when the format is a
  named constant (the run-time output was "Invalid % index 2 ..." and `100\ sure`); write `#string,\% END` to enable
  the escape (0.2.010). `%%` means two adjacent arguments since 0.2.022. All verified with print.
- `#insert` text is parsed like source at that position, so backticks, `#if` and further `#insert`s work inside.

## From Code to nodes and back

```jai
root, nodes := compiler_get_nodes(code);    // root: *Code_Node; nodes: every node, children before parents
// ... inspect or edit (each call returns a fresh copy you own) ...
new_code := compiler_get_code(root, code);  // back to Code; the second argument supplies the scope
```
- Rendering: `print_expression(*builder, node)` from modules/Program_Print turns nodes back into source text (21,
  22). Program_Print is also a plugin (`+Program_Print`, not probed here).
- Traversal: `nodes` (flattened) is usually enough. modules/Code_Visit adds `get_subexpressions(node, *array)`,
  `get_recursive_nodes_breadth_first(node, *array)`, `get_recursive_nodes_depth_first(node, *array)` and a macro
  `visit_pre_and_postorder(node, #code { ... })` that provides `it` and `preorder` (all verified on a small block).
- Building nodes: `New(Code_Ident)` etc. (the struct default sets `kind`), `make_integer_literal(v)`,
  `make_string_literal(s)`; fill the fields a parser would fill (see 39, which builds a call node:
  `procedure_expression = ident`, `arguments_unsorted = [ {expression = literal} ]`). Leave fields marked
  `:LeaveEmpty` in Compiler.jai empty; identifiers are resolved when the code is typechecked again.
- Locations: `make_location(node)` gives a Source_Code_Location for `compiler_report`; `get_filename(node)`;
  each node has `enclosing_load` (the Message_File) and `l0, c0, l1, c1` (start/end line and byte column).

## The node structs you will use most

All start with `using base: Code_Node` (`kind`, `node_flags`, `type: *Type_Info` (set after typechecking),
location, `serial`). Cast after checking `kind`:

| kind | struct | fields worth knowing |
|---|---|---|
| BLOCK | Code_Block | `statements`, `members`, `parent`, `block_type` (IMPERATIVE, DATA_DECLARATIONS, ARGUMENTS, ...) |
| LITERAL | Code_Literal | `value_type` (NUMBER, STRING, BOOLEAN, ARRAY, STRUCT, POINTER, TYPE_INFO); `_s64`, `_u64`, `_float64`, `_string`; `value_flags` (HEX, FLOAT, HERE_STRING, ...) |
| IDENT | Code_Ident | `name`, `resolved_declaration` (after typechecking) |
| UNARY_OPERATOR / BINARY_OPERATOR | Code_Unary_Operator / Code_Binary_Operator | `operator_type`, `subexpression` / `left`, `right` |
| PROCEDURE_CALL | Code_Procedure_Call | `procedure_expression` (as written), `resolved_procedure_expression` (after overload/polymorph resolution; a Code_Procedure_Header or, for struct instantiation, a Code_Struct), `overloads`, `arguments_unsorted` ([] Code_Argument {expression, name}), `arguments_sorted`, `macro_expansion_block`, `context_modification` (`,,`) |
| DECLARATION | Code_Declaration | `name`, `type_inst`, `expression`, `flags` (IS_CONSTANT, IS_GLOBAL, NO_RESET, PROGRAM_EXPORT, ...), `notes` |
| PROCEDURE_HEADER | Code_Procedure_Header | `name`, `arguments`, `returns` (Code_Declaration each), `procedure_flags` (POLYMORPHIC, MACRO, COMPILE_TIME_ONLY, SYMMETRIC, ...), `notes`, `body_or_null`, `polymorph_source_header`, `modify_directives` |
| PROCEDURE_BODY | Code_Procedure_Body | `block`, `header`, `body_flags` (ALREADY_MODIFIED) |
| STRUCT | Code_Struct | `block`, `defined_type` (*Type_Info_Struct), `notes`, `arguments_block`, `constants_block` |
| IF | Code_If | `condition`, `then_block`, `else_block`, `if_flags` (IS_SWITCH_STATEMENT, IS_IFX, IS_STATIC) |
| FOR / WHILE / RETURN / CAST / CASE / DEFER / USING | Code_For, Code_While, Code_Return, Code_Cast, Code_Case, Code_Defer, Code_Using | iteration and control-flow details; Code_For has `for_flags`, `macro_expansion_procedure_call` |
| TYPE_INSTANTIATION | Code_Type_Instantiation | how a type was written (`pointer_to`, `array_element_type`, `inst_flags` VARARGS / RESIZABLE / INTERFACE, `must_implement` for `$T/X`); 34 uses VARARGS to print `..T` |
| DIRECTIVE_INSERT / DIRECTIVE_RUN / NOTE / ... | Code_Directive_Insert, Code_Directive_Run, Code_Note (`text`) | one struct per directive |

- `Operator_Type`: single-character operators are stored as their ASCII code (`op.operator_type == #char "+"`, as in
  21); multi-character ones have names (IS_EQUAL, IS_NOT_EQUAL, LOGICAL_AND, LOGICAL_OR, LESS_OR_EQUAL,
  GREATER_OR_EQUAL, SHIFT_LEFT, PLUS_ASSIGN, ..., ARRAY_SUBSCRIPT); `operator_to_string(op)` names the long ones.
- `type` on a node is only meaningful for typechecked code (messages from a metaprogram, `#code,typed`); 36 checks
  `op.left.type.type == .FLOAT`.
- Renamed node structs (old code): `Code_Directive_If` → `Code_If` with `IS_STATIC` (0.1.084);
  `Code_Size_Or_Type_Info` → `Code_Type_Query` (size_of, type_info, initializer_of) and `Code_Expression_Query`
  (type_of, is_constant, code_of) (0.1.091). Both old names are now undeclared (41).

## Scope rules (verified)

| Situation | Names resolve in |
|---|---|
| `#insert c` where c came from the caller's `#code` | the caller's scope (caller locals visible) |
| `#insert,scope() c` inside a macro | the macro body at the insertion point (macro locals visible, caller locals not) |
| string insert, or Code from `compiler_get_code(root)` without a scope argument | the insertion point |
| `compiler_get_code(root, original)` | the scope of `original` |
| `add_build_string(text, w)` | the main program's file scope of workspace w (overloads take a Code or a Message to choose a scope; see bundle example `add_build_string_into_specific_scope`) |

## Worked uses in the examples

- 20: generate statements, struct members and a file-scope constant from strings; constant unrolling.
- 21: a macro that edits the received Code (rewrites `+` to `*`) and inserts the result.
- 22: assertion macro that prints its own condition (`#caller_code`), `code_of`, labelled values with `..Code`.
- 23: `#placeholder` filled by `add_build_string(text, -1)` from a #run; `#exists`.
- 31: polymorphic serializer whose body is generated from `type_info(T)`.
- 34–36, 39: the same node types seen from a build metaprogram (typechecked, with `type` and resolved calls).

## Real-world reading

- `jai-parser-source` is an independent parser with one small test input per newer syntax form: useful to see what
  current code looks like before you generate it.
- modules/Print_Vars (`..Code` + Program_Print), modules/Soa (#insert in a polymorphic struct body),
  modules/Code_Visit, and the bundle's `examples/self_inspect.jai` (`code_of` + `compiler_get_nodes` on a procedure
  of the same program) and `examples/code_type.jai` (types of Code at compile time).
