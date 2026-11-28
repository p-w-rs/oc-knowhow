// #modify runs compile-time code between a procedure's (or struct's) header and body, after the
// polymorph variables are solved. Inside it the variables are mutable Type values (cast to
// *Type_Info to inspect them); return true to accept, or `false, "reason"` to reject.
// Uses: fill return-type variables the caller cannot supply, collapse many polymorphs into few
// (less code bloat), and allow overloads with identical headers that accept disjoint type sets.
// EXPECT-COMPILE: [compile time] sum() compiled for T=s64
// EXPECT-COMPILE: [compile time] sum() compiled for T=float64
// EXPECT: sum(u8s) = 600 as u64
// EXPECT: sum(s16s) = -6 as s64
// EXPECT: sum(f32s) = 1.5 as float64
// EXPECT: encode scalar 42 (s64)
// EXPECT: encode struct Point with 2 members

#import "Basic";

// Widen every integer to 64 bits and every float to float64: 3 input types -> 2 compiled copies.
sum :: (values: [] $T) -> $R
#modify {
    info := cast(*Type_Info) T;
    if info.type == .INTEGER {
        R = ifx (cast(*Type_Info_Integer) info).signed then s64 else u64;
        return true;
    }
    if info.type == .FLOAT { R = float64; return true; }
    return false, "sum() needs integers or floats";
}
{
    #run print("[compile time] sum() compiled for T=%\n", ifx R == float64 then "float64" else "s64");
    total: R;
    for values total += cast(R) it;
    return total;
}

// Two overloads with the SAME header; #modify decides which one matches.
encode :: (x: $T)
#modify { info := cast(*Type_Info) T; return info.type == .INTEGER || info.type == .FLOAT; }
{ print("encode scalar % (%)\n", x, T); }

encode :: (x: $T)
#modify { return (cast(*Type_Info) T).type == .STRUCT, "encode() for structs only"; }
{ print("encode struct % with % members\n", T, type_info(T).members.count); }

Point :: struct { x, y: int; }

main :: () {
    s1 := sum(u8.[200, 200, 200]);       // would overflow as u8
    s2 := sum(s16.[-1, -2, -3]);
    s3 := sum(float32.[0.5, 1.0]);
    print("sum(u8s) = % as %\n", s1, type_of(s1));
    print("sum(s16s) = % as %\n", s2, type_of(s2));
    print("sum(f32s) = % as %\n", s3, type_of(s3));
    encode(42);
    encode(Point.{1, 2});
}
