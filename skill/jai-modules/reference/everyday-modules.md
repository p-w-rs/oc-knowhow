# Everyday modules in practice (beta 0.2.032)

Behaviour checked by running the examples named in brackets (`examples/jai/jai-modules/NN_*`, all passing on macOS
arm64 and two Linux x64 machines). Signatures: read the source (`library_search query="table_find"
sources=["jai-modules-src"]`, or `grep -n "^name ::" ~/jai/current/modules/<Module>/*.jai`). Allocation:
procedures that return new memory use `context.allocator` unless they say "temporary"; push another allocator
per call with `f(x,, temp)` (jai-systems covers allocators and temporary storage).

## Basic: printing and formatting [15, 16]

- `print(format, args..)`: every bare `%` takes the next argument; `%N` picks argument N (1-based, may repeat);
  `%00` prints nothing; a literal percent is `\%` (`%%` now means two arguments, changed 0.2.022). No `%d`/`%s`.
- Options by wrapping the value: `FormatInt.{value = x, base = 16, minimum_digits = 5, digits_per_comma = 3,
  comma_string = ","}`, `FormatFloat.{value = f, width = 8, trailing_width = 3, mode = .SCIENTIFIC, zero_removal =
  .NO}`, `FormatStruct`, `FormatArray`. The older helper procedures `formatInt(...)`, `formatFloat(...)` still work.
- Defaults: structs print `{1, 2.5, "p"}` up to 5 members, then `{a = 1; b = 2; ...}`; enums print member names,
  `enum_flags` print `READ | EXEC`; arrays `[1, 2, 3]`; `null` pointers `null`; types by name (`[3] s64`).
  An untyped float literal is `float32` (`2.5e10` prints `24999999488`).
- Program-wide defaults: `context.print_style.default_format_int/float/struct/array`.
- `sprint` (allocates), `tprint` (temporary storage), `print_to_builder(*b, ...)`, `write_string` (no formatting),
  `print(..., to_standard_error = true)`, `log(...)` / `log_error(...)` (through `context.logger`).

## Basic: String_Builder, strings, conversions [16, 19, 31]

- `b: String_Builder;` (no init needed), `append(*b, "text")`, `append(*b, byte)`, `print_to_builder(*b, ...)`,
  `builder_string_length(*b)` (constant time since 0.2.031), `builder_to_string(*b)` (copies out with
  `context.allocator` and resets; `do_reset = false` to keep), `write_builder(*b)`.
- `copy_string`, `to_c_string` (heap) / `temp_c_string` (temporary), `to_string(*u8)` (borrow a C string),
  `to_string(ptr, count)`, `to_upper(c)`/`to_lower(c)` work on **one byte** (whole strings: String module).
- Numbers from text: `to_integer(s) -> value, ok, rest`; `string_to_int(s, base = 10, T) -> value, ok, rest`;
  `string_to_float(s) -> value, ok, rest`; **`string_to_float_new(s) -> ok, value, rest`** (0.2.027, success
  first, preferred in new code; the old one will be deprecated).

## Basic: arrays [17]

- `[..] T` dynamic arrays: `array_add(*a, x)`, `array_add(*a, x, y, z)`, `p := array_add(*a)` (new zeroed slot),
  `array_insert_at`, `array_ordered_remove_by_index/value`, `array_unordered_remove_by_index/value` (fills the hole
  with the last element), `array_find(a, x) -> found, index` (optional `compare` since 0.2.029),
  `array_add_if_unique`, `peek`, `pop`, `array_view(a, start, count)` (no copy), `array_copy`, `array_reserve`,
  `array_resize`, `array_reset` (frees), `array_reset_keeping_memory`, `array_free`.
- In a `for`, `remove it` deletes the current element (unordered) without disturbing the iteration.
- `NewArray(n, T)` returns a `[] T` view of new zeroed memory; `New(T)` a pointer. The parameter to skip zeroing is
  **`initialize = false`** (renamed from `initialized` in 0.2.032, hard error for old code [40]).

## Basic: time [16]

- `Apollo_Time` is a 128-bit time (femtoseconds). `current_time_monotonic()` for durations,
  `current_time_consensus()` for wall-clock; differences are Apollo_Time; `to_milliseconds(d)`, `to_seconds`,
  `to_nanoseconds`, `to_float64_seconds(d) -> f, ok`; `seconds_to_apollo(n)`, `milliseconds_to_apollo` ...;
  `APOLLO_TIME_FOR_JAN_1_1970` for Unix times.
- `to_calendar(t, .UTC or .LOCAL) -> Calendar_Time` (fields `year`, `month_starting_at_0`,
  `day_of_month_starting_at_0`, `day_of_week_starting_at_0` (0 = Sunday), `hour`, `minute`, `second`,
  `millisecond`), `calendar_to_iso_string` → `2001-09-09T01:46:40.000Z`, `calendar_to_string` →
  `9 September 2001, 01:46:40`. Pre-1970 values made `to_calendar` log an out-of-range error on macOS.
- `seconds_since_init()` (float64) replaces the removed `get_time()`; `sleep_milliseconds(ms)`.

## String [18, 19]

- Searching: `contains(s, sub) -> found, remainder` (two results since 0.1.096), `contains_nocase`,
  `begins_with`/`ends_with` (+ `_nocase`), `find_index_from_left/right(s, byte | substring) -> index or -1`
  (replaced `index_of_string`), `find_index_of_any_from_left/right`.
- Splitting: `split(s, ";" or #char ";")` returns views but allocates the result array with `context.allocator`
  (write `split(s, sep,, temp)` for throwaway use; it used temporary storage before 0.1.080);
  `split_from_left/right(s, sep) -> found, left, right` (views); `_by_any` variants.
- `trim`, `trim_left`, `trim_right` (views; default characters space, tab, CR, LF); `join(a, b, c, separator = ", ")`
  or `join(..array, separator = "/")` (replaced `concatenate`); `replace(s, old, new) -> result, count`.
- Case: `to_upper_copy` / `to_lower_copy` (allocate), `to_upper_in_place` / `to_lower_in_place` (not on literals:
  read-only memory). ASCII only (`"grüße"` → `GRüßE`).
- Paths: `path_filename`, `path_extension`, `path_strip_extension`, `path_strip_filename`, `path_decomp`,
  `path_join(a, b, c)` (0.2.018; drops a trailing separator per component; result in `context.allocator`),
  `path_overwrite_separators`, `is_absolute_path`.
- Scanning a line: `parse_int(*cursor)`, `parse_float(*cursor)`, `parse_token(*cursor)`, `parse_bool`, `parse_enum`
  advance a `*string` cursor and return `value, ok`; `scan2(text, "%,%", *a, *b)`.
- `compare(a, b)` (byte order, negative/zero/positive) is the comparator for sorting strings.

## File and File_Utilities [20]

- Whole files: `read_entire_file(name, zero_terminated = false, log_errors = true) -> data, ok`;
  `write_entire_file(name, string | (data, count) | *String_Builder) -> ok`.
- Handles: `file_open(name, for_writing = false, keep_existing_content = false, log_errors = true) -> File, ok`,
  `file_read(f, buffer, n) -> ok, read`, `file_write(*f, string | data, count | *builder)`,
  `file_seek(f, pos, .START | .CURRENT | .END)`, `file_tell`, `file_length`, `file_flush` (0.2.017), `file_close(*f)`.
  Append = open with `keep_existing_content = true`, seek `.END`, write.
- Directories and names: `make_directory_if_it_does_not_exist(name, recursive = true)`, `delete_directory` (whole
  tree), `file_delete`, `file_move`, `file_link`, `get_absolute_path` (uses `realpath` on Unix: **the path must
  exist**, otherwise it logs an error and fails).
- File_Utilities: `file_exists`, `is_directory -> bool, ok`, `file_list(dir, recursive)` (files only; order is
  OS-dependent: sort it), `visit_files(dir, recursive, user_data, proc, visit_files = true, visit_directories =
  false, visit_symlinks = true, follow_directory_symlinks = true)` (the old `follow_symlinks` argument is gone),
  `File_Visit_Info` (`short_name`, `full_name`, `is_directory`, `is_symlink`, `size`, `modification_time`,
  `descend_into_directory`), `copy_file`, `copy_directory`, `file_modtime(path) -> Apollo_Time, ok` (0.2.025),
  `file_modtime_and_size`, `atomic_file_replace_or_just_rename_if_destination_file_does_not_exist`.
- Errors: most calls log the OS error themselves and return false.

## Hash_Table [21, 39]

- `t: Table(Key, Value);` is ready to use (no `init`; `init(*t, n)` is deprecated since 0.2.029 and warns). Optional
  type parameters: `given_hash_function`, `given_compare_function`, `LOAD_FACTOR_PERCENT = 70`, `REFILL_REMOVED`.
- `table_add` (does **not** check for an existing key: duplicates accumulate), `table_set` (add or replace),
  `table_find(*t, k) -> found, value` (**success first since 0.2.018**), `table_find_pointer` (null if absent),
  `table_contains`, `table_remove -> found, old_value`, `find_or_add -> *value, newly_added`,
  `table_find_multiple` (temporary array), `table_remove_multiple`, `table_resize(*t, n)` (presize),
  `table_reset` (frees memory since 0.2.029), `table_reset_keeping_memory`, `deinit` (was `uninit`).
- `for t` gives `it` = value, `it_index` = key, in slot order; `for * t` gives pointers; `remove it` works.
- Keys: `Hash.get_hash` handles integers, floats, bools, enums, pointers, strings and arrays. **Struct keys need a hash
  and compare procedure** (`Table(Point, V, point_hash, point_eq)`), otherwise a compile error inside Hash_Table.
  Case-insensitive string keys: hash a lowered copy, compare with `equal_nocase`.
- **Trap when updating old code**: `value, found := table_find(...)` (pre-0.2.018 order) still compiles when the
  value converts to bool, and silently swaps the two [39].

## Command_Line [22]

- `ok, opts, is_set, free_args := parse_arguments(Options)` where `Options` is a struct with defaults; flags are
  `-member` (one dash; `--name` is rejected unless you pass `Default_Argument_Flags | .DOUBLE_DASH_REQUIRED`). Bools
  take no value, `[N] T` takes N values, enum values are matched by member name, case-sensitive. Words without a
  dash and everything after `--` are free arguments. `@"?text"` notes become `-help` output (sorted, aligned).
- `Is_Set(Options)` has a bool per member telling what the user set explicitly.
- On errors (unknown flag, bad number, unknown enum value) it prints a message and returns `ok = false`; the exit
  code is up to you. `-help` also returns false. `parse_arguments(T, args = list)` parses any list (element 0 must
  be a program name). `get_command_line_arguments()` returns all arguments including argv[0].
- Limits: `enum_flags` members are not supported; dynamic arrays as members are not supported.

## Process [23]

- `result, out, err, timed_out := run_command("prog", "arg", ..., capture_and_return_output = true, timeout_ms = n,
  working_directory = dir, print_captured_output = false)`; arguments are passed as an array (no shell parsing).
- `Process_Result`: `type` (`.EXITED`, `.SIGNALED`, `.FAILED_TO_LAUNCH`, `.STILL_RUNNING`), `exit_code`, `signal`.
  A signal-killed child reported `SIGNALED`, `signal = 9`, `exit_code = -1` (non-zero since 0.2.031); a missing
  program `FAILED_TO_LAUNCH` (the module logs the execvp error); a timeout kills the child (`SIGNALED`).
- Unix: bare program names are searched in `PATH` only; a relative program path is resolved against
  `working_directory`. Windows resolves against the parent's directory (module comment).
- Lower level: `create_process(*p, args.., capture_and_return_output = true)`, `read_from_process(*p, out_buf,
  err_buf, timeout_ms) -> ok, n_out, n_err` until `p.output.eof`, `write_to_process`, `get_process_result(*p,
  timeout_ms)`, `kill_process`, `deinit(*p)`. `break_command_into_strings("cc -o \"a b\" x.c")` splits a command
  line (temporary storage).

## Random and PCG [24]

- Random: state in `context.random_state` (per thread). `random_seed(u64)`, `random_get() -> u64`,
  `random_get_zero_to_one() -> float`, `random_get_within_range(lo, hi) -> float`, `*_new` float64 variants, and the
  same with an explicit `*Random_State` first. Time seed: `random_seed(cast(S128) current_time_monotonic())` (the
  uncast Apollo_Time does not match any overload in 0.2.032).
- Same seed → same sequence, identical on arm64 and x64 (checked).
- PCG: `random_seed(u32)`, `random_get() -> u32`, `random_get_within_bound(n)`; explicit `*u64` state variants;
  module header says untested. Import one of them unqualified at most (name clash).

## Math [25]

- `Vector2/3/4` (float32 members, `#overlay` views: `v.xy`, `v.component[i]`), `Quaternion` (identity by default),
  `Matrix2/3/4/4x3` (row-major; translation in `_14 _24 _34`), operators `+ - * /` and `==`.
- `dot`, `cross`, `length`, `length_squared`, `normalize`, `unit_vector`, `lerp`, `slerp`, `nlerp`, `rotate(v, q)`,
  `set_from_axis_and_angle(*q, axis, angle)`, `make_translation_matrix4`, `make_scale_matrix4`,
  `make_look_at_matrix`, `make_projection_matrix`, `orthographic_projection_matrix`, `inverse(m) -> ok, m`,
  `transpose`, `determinant`; constants `PI`, `TAU`, `PI64`, `FLOAT32_MAX`...; `sin/cos/sqrt` on float32 and float64.
- Old forms: `make_vector2(x, y)` / `make_vector3(x, y, z)` no longer match (removed 0.2.002; other overloads
  remain) → `Vector3.{x, y, z}`; `matrix4_identity()` → `Matrix4_Identity`.
- Compare floats with `Sloppy_Math.values_are_close`. For serious linear algebra see robot-math (C++/Python).

## Unicode [26]

- Strings are UTF-8 bytes: `s.count` is bytes and `for` over a string visits bytes. `for :utf8_iter s { it, it_index }`
  iterates code points (only with the implicit `it`; naming the variable fails inside the module).
- `utf8_next_character(*s) -> code, result` consumes one; `character_utf8_to_utf32(ptr, len) -> code, used,
  result` (`.SOURCE_EXHAUSTED`, `.SOURCE_ILLEGAL` → U+FFFD); `character_utf32_to_utf8(code) -> string`.
- No Unicode case mapping, normalization or width in the bundle.

## Text_File_Handler [27]

- `handler: Text_File_Handler;` then `start_file(*h, short_name, path)` or `start_from_memory(*h, name, path,
  data)`; with `do_version_number` (default true) the first line must be `[N]` → `h.version`.
- `consume_next_line(*h) -> line, found` skips blank lines and `#` comments (also trailing ones; set
  `strip_comments_from_ends_of_lines = false` to allow `#` in values), tracks `h.line_number`.
- `break_by_spaces(line) -> first_word, rest`; `error(h, fmt, ..)` / `warn(h, ...)` log with file and line
  (stderr); `h.failed` is sticky. Shortcuts: `file_to_array`, `file_to_table` (also from memory).

## Sorting, hashing, encodings [28]

- `quick_sort(array, compare)` (in place, returns the array), `quick_sort(array, key_proc)`,
  `quick_sort(array, user_data, compare3)` (0.2.031); `compare_floats`, `compare_strings`; `intro_sort(array,
  (T, T) -> int)`. Basic's `bubble_sort` was removed (0.2.022).
- `fnv1a_hash(data, count)`, `get_hash(x)`, `crc64(s)` (CRC-64/WE), `md5(s) -> hex`, `base64_encode/decode`,
  `base64url_*`, `xxHash.native_XXH64(data, len, seed)` / `native_XXH32`: all cross-checked with reference
  implementations.

## System and CPU [module map]

- `get_number_of_processors()` defaults to `.PERFORMANCE_LOGICAL` (8 on a 12-core M-series Mac; `.ALL_LOGICAL` gave
  12), `get_path_of_running_executable()` (temporary), `get_home_directory() -> path, ok`, `get_username`,
  `get_machinename`, `get_error_value_and_string()`.
- x64 feature detection: `#if CPU == .X64 { #import "Machine_X64"; }` then `info := get_cpu_info();
  check_feature(info.feature_leaves, .AVX2)`.

## Old → current, for these modules

| Old (still in tutorials) | Current (0.2.032) | Changed |
|---|---|---|
| `value, found := table_find(*t, k)` | `found, value := table_find(*t, k)` (old order compiles, swapped) | 0.2.018 |
| `init(*table, n)` | nothing, or `table_resize(*t, n)` (init warns) | 0.2.029 |
| `table_reset` keeping memory | `table_reset_keeping_memory` (`table_reset` frees) | 0.2.029 |
| `uninit(*t)` | `deinit(*t)` | 0.1.050 |
| `New(T, initialized = false)` | `New(T, initialize = false)` | 0.2.032 |
| `to_lower(s)` on a string | `to_lower_in_place(s)` / `to_lower_copy(s)` | 0.1.004 |
| `index_of_string`, `concatenate` | `find_index_from_left`, `join` | removed 0.1.028 |
| `found := contains(s, x)` | `found, rest := contains(s, x)` | 0.1.096 |
| `split(...)` result in temp | `split(...,, temp)` | 0.1.080 |
| `f, ok := string_to_float(s)` | `ok, f := string_to_float_new(s)` | 0.2.027 |
| `make_vector2(1, 2)` | `Vector2.{1, 2}` | 0.2.002 |
| `bubble_sort`, `Swap` | `quick_sort`/`intro_sort`, `swap(*a, *b)` | 0.2.022 |
| `get_time()`, `get_system_time()` | `seconds_since_init()`, `current_time_consensus()` + `to_calendar` | 0.2.002 |
| `visit_files(..., follow_symlinks = x)` | `visit_symlinks`, `follow_directory_symlinks` | 0.1.090 |
| `print("100%%")` | `print("100\%")` | 0.2.022 |
| `#import "Tagged_Union"` | language `union kind: Enum { ... }` (jai skill) | 0.2.025 |
