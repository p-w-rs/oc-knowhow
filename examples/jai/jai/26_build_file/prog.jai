// The program compiled by build.jai. Built alone (`jai prog.jai`) the += below would wrap silently.

#import "Basic";

main :: () {
    args := get_command_line_arguments();
    total: s32 = 2147483645 + cast(s32) args.count;   // 2147483646, one below S32_MAX
    print("s32 sum so far: %\n", total);
    total += 5;                                       // overflows
    print("never reached: %\n", total);
}
