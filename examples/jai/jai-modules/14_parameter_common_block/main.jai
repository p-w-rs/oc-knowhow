// A block { ... } after the parameter lists is compiled once, before the
// parameters, so it can declare the types the parameters use. Callers pass enum
// values with .NAME; the parameter value is readable as Instance.PARAM through a
// named import (not through an unqualified one), and the common-block type itself
// is not exported to importers (0.2.032).
// EXPECT: 2.5 m = 2.5 m
// EXPECT: 2.5 m = 8.202 ft
// EXPECT: Feet.SYSTEM = IMPERIAL

#import "Basic";
Metric :: #import "Units";
Feet   :: #import "Units"(SYSTEM = .IMPERIAL);

main :: () {
    print("2.5 m = % %\n", Metric.from_meters(2.5), Metric.unit_name());
    print("2.5 m = % %\n", FormatFloat.{value = Feet.from_meters(2.5), trailing_width = 3}, Feet.unit_name());
    print("Feet.SYSTEM = %\n", Feet.SYSTEM);
}
