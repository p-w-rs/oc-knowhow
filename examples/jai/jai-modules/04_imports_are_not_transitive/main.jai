// A module's own imports are not passed on: Logger imports Basic, but this file
// still has to import Basic itself to call print. (Every module is compiled in its
// own scope and links only what it imports.)
// EXPECT-COMPILE-ERROR: Undeclared identifier 'print'

#import "Logger";

main :: () {
    log_line("from main");
    print("this needs #import \"Basic\" in this file\n");
}
