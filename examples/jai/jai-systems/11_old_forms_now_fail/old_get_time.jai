// Removed in 0.2.002: seconds_since_init() (from its first call), or
// current_time_monotonic() differences converted with to_float64_seconds().
#import "Basic";
main :: () { t := get_time(); }
