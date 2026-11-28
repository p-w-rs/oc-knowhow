#import "Basic";

fnv1a :: (s: string) -> u32 #no_aoc {          // intentional wraparound: opt out for the whole procedure
    h: u32 = 2166136261;
    for 0..s.count-1 {
        h ^= s[it];
        h *= 16777619;
    }
    return h;
}

main :: () {
    print("fnv-1a hash with #no_aoc: %\n", fnv1a("jai"));

    x: u32 = 0xffff_ffff;
    #no_aoc { x += 1; }                           // block form
    print("wrapping block with #no_aoc: %\n", x);

    big: s32 = 2147483647;
    one := cast(s32) (get_command_line_arguments().count);   // 1, unknown to the compiler
    big += one;                                   // checked: panics here
    print("not reached: %\n", big);
}
