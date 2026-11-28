open_account :: (name: string) -> string {
    return tprint("account for %", normalize_name(name));
}

#scope_module
normalize_name :: (name: string) -> string { return to_upper_copy(name); }

#import "Basic";
#import "String";
