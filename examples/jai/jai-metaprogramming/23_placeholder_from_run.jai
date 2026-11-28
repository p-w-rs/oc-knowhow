// #placeholder declares a name that compile-time code promises to define later. Here a #run in the
// same program fills it with add_build_string(text, -1) (-1 = the current workspace). The more
// common producer is a build metaprogram (see 35_build_generate_code/). #exists(name) asks, as a
// constant, whether a declaration exists, like `defined` in C's #ifdef.
// EXPECT-COMPILE: [compile time] generating SIN_TABLE with 8 entries
// EXPECT: SIN_TABLE.count = 8, first = 0, third = 0.707
// EXPECT: has SIN_TABLE: true, has COS_TABLE: false

#import "Basic";
#import "Compiler";
#import "Math";

#placeholder SIN_TABLE;

#run {
    N :: 8;
    print("[compile time] generating SIN_TABLE with % entries\n", N);
    sb: String_Builder;
    append(*sb, "SIN_TABLE :: float.[");
    for 0..N-1 {
        if it append(*sb, ", ");
        print_to_builder(*sb, "%", formatFloat(sin(it * TAU / N), trailing_width = 4));
    }
    append(*sb, "];");
    add_build_string(builder_to_string(*sb), -1);
}

main :: () {
    print("SIN_TABLE.count = %, first = %, third = %\n", SIN_TABLE.count,
          formatFloat(SIN_TABLE[0], trailing_width = 0), formatFloat(SIN_TABLE[1], trailing_width = 3));
    print("has SIN_TABLE: %, has COS_TABLE: %\n", #exists(SIN_TABLE), #exists(COS_TABLE));
}
