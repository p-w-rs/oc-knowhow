// Single-file module: modules/Shout.jai is found by #import "Shout".
shout :: (s: string) -> string {
    return to_upper_copy(s);
}

#scope_file
#import "String";
