// Renamed in 0.2.032 with no deprecation period: New(T, initialize = false).
#import "Basic";
Particle :: struct { x, y: float; }
main :: () { p := New(Particle, initialized = false); }
