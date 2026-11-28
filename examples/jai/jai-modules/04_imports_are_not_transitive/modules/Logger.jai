#import "Basic";   // at export scope, but imports never re-export by themselves

log_line :: (s: string) { print("[log] %\n", s); }
