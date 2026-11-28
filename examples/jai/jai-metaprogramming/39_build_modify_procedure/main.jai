// Target program: procedures tagged @Trace get a call to trace_enter() injected at the top of
// their body by build.jai. The source here never calls trace_enter itself.
#import "Basic";

trace_enter :: (name: string) { print("-> %\n", name); }

load_level :: (n: int) -> int { return n * 2; } @Trace
save_game  :: () { print("   saving\n"); }       @Trace
untraced   :: () { print("   untraced work\n"); }

main :: () {
    x := load_level(21);
    save_game();
    untraced();
    print("x = %\n", x);
}
