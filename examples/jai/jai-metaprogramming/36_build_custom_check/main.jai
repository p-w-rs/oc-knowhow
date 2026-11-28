// Target program with two house-rule violations that the plain compiler accepts.
#import "Basic";

point_2d :: struct { x, y: float; }      // rule: struct names start with a capital letter

main :: () {
    p := point_2d.{0.1 * 3, 0.3};
    if p.x == p.y print("equal\n");      // rule: no == / != on floats
    else          print("not equal\n");
}
