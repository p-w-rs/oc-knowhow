// Library source: #program_export keeps the symbol visible under its plain name (C ABI via #c_call),
// so C or another language can link against the library.
#program_export
add_numbers :: (a: s32, b: s32) -> s32 #c_call {
    return a + b;
}
