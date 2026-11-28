// Procedures that a C program can call. #program_export keeps the symbol under its
// plain name; #c_call gives it the C calling convention (and no implicit context).

Stats :: struct {
    count: s64;
    mean:  float64;
}

#program_export
jai_add :: (a: s32, b: s32) -> s32 #c_call {
    return a + b;
}

#program_export
jai_stats :: (values: *float64, count: s64) -> Stats #c_call {
    result: Stats;
    result.count = count;
    for 0..count-1  result.mean += values[it];
    if count  result.mean /= cast(float64) count;
    return result;
}

#program_export
jai_greeting :: (name: *u8) -> *u8 #c_call {
    push_context {                         // sprint/to_c_string need a context
        return to_c_string(sprint("hello, %, from Jai", to_string(name)));   // heap memory, never freed in this demo
    }
}

#import "Basic";
