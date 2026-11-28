// #if chooses code at compile time. Unlike C's #if it is not a preprocessor: both branches must
// parse, but only the chosen one is typechecked. Its braces do NOT open a scope, so a branch can
// declare things for the surrounding code. #if also works inside structs and enums, and #ifx is
// the expression form (the value of a block is its last expression).
// EXPECT: platform family: unix
// EXPECT: Color has 4 members; Settings = {width = 800, height = 600, debug_overlay = true}
// EXPECT: buffer bytes: 4096
// EXPECT: chosen = 42

#import "Basic";

DEBUG_BUILD :: true;     // in real code this comes from a module parameter or the build metaprogram

Color :: enum {
    RED; GREEN; BLUE;
    #if DEBUG_BUILD { DEBUG_MAGENTA; }
}

Settings :: struct {
    width  := 800;
    height := 600;
    #if DEBUG_BUILD  debug_overlay := true;
}

main :: () {
    #if OS == .WINDOWS {
        family := "windows";
    } else #if OS == .MACOS || OS == .LINUX {
        family := "unix";
    } else {
        family := "other";
    }
    print("platform family: %\n", family);    // 'family' is visible: #if made no new scope

    s: Settings;
    print("Color has % members; Settings = {width = %, height = %, debug_overlay = %}\n",
          enum_highest_value(Color) + 1, s.width, s.height, s.debug_overlay);

    BUFFER :: #ifx DEBUG_BUILD then 4096 else 65536;
    print("buffer bytes: %\n", BUFFER);

    chosen := #ifx size_of(int) == 8 {
        k := 6;
        k * 7;              // last expression is the value
    } else {
        0;
    };
    print("chosen = %\n", chosen);

    #if false {
        // Never typechecked, so undeclared names are fine here (it must still parse).
        this_function_does_not_exist(42);
    }
}
