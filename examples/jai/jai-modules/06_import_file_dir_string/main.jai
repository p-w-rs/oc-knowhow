// #import variants that skip the search path:
//   #import,file "path.jai"  a single file as a module (path relative to THIS file)
//   #import,dir  "path"      a folder module (needs path/module.jai)
//   #import,string "code"    code from a string literal, compiled as a module
// Unlike #load, these create a separate module scope that cannot see your program.
// EXPECT: triple(4) = 12
// EXPECT: square area = 9
// EXPECT: plus_one(41) = 42
// EXPECT: from sub/helpers.jai: 15

#import "Basic";
Util   :: #import,file "vendor/util.jai";
Shapes :: #import,dir  "vendor/Shapes";
#import,string "plus_one :: (x: int) -> int { return x + 1; }";
#load "sub/helpers.jai";

main :: () {
    print("triple(4) = %\n", Util.triple(4));
    print("square area = %\n", Shapes.area(Shapes.Square.{side = 3}));
    print("plus_one(41) = %\n", plus_one(41));
    print("from sub/helpers.jai: %\n", helper_value());
}
