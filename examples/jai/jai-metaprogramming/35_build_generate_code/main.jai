// Target program: commands register themselves just by carrying the @Command note.
// COMMANDS does not exist in this file; build.jai generates it. (Compiling main.jai alone fails
// with "Placeholder for identifier 'COMMANDS' was never filled.")
#import "Basic";

Command :: struct {
    name: string;
    proc: () -> ();
}

#placeholder COMMANDS;     // build.jai promises to define this

greet :: () { print("hello!\n"); } @Command
quit  :: () { print("bye.\n"); }   @Command
reset :: () { print("state reset\n"); } @Command
internal_helper :: () {}     // no note: not a command

run_command :: (name: string) {
    for COMMANDS if it.name == name { it.proc(); return; }
    print("unknown command '%'\n", name);
}

main :: () {
    print("% commands registered\n", COMMANDS.count);
    run_command("greet");
    run_command("reset");
    run_command("internal_helper");
}
