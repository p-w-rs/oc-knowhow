// The target program for build.jai. Compiling this file alone also works (`jai main.jai`).
#import "Basic";
#load "shapes.jai";

main :: () {
    s := Square.{side = 3};
    print("area of the square: %\n", area(s));
}
