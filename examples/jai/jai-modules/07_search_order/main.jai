// Where #import "Name" looks, in order (0.2.032):
//   1. each -import_dir (relative paths are taken relative to the first compiled file)
//   2. ./modules next to the first compiled file
//   3. the compiler's own modules/ folder
// The first match wins, for every importer in the program, so modules/Sort.jai
// here also replaces the bundled Sort for any bundled module that imports it.
// JAI-ARGS: -import_dir vendor
// EXPECT: 0: <here>/vendor
// EXPECT: 1: <here>/modules
// EXPECT: 2: <compiler>/modules/
// EXPECT: Sort comes from: the local modules folder
// EXPECT: Vendored comes from: vendor (found through -import_dir)

#import "Basic";
#import "String";
#import "Sort";       // shadowed by ./modules/Sort.jai
#import "Vendored";   // only exists in ./vendor

SEARCH_PATH :: #run describe_import_path();

describe_import_path :: () -> string {
    #import "Compiler";
    b: String_Builder;
    for get_build_options().import_path {
        // Print machine-independent names: paths under this example's folder vs the compiler's.
        shown := ifx begins_with(it, #filepath) then tprint("<here>/%", slice(it, #filepath.count, it.count - #filepath.count))
                 else "<compiler>/modules/";
        print_to_builder(*b, "%: %\n", it_index, shown);
    }
    return builder_to_string(*b);
}

main :: () {
    print("%", SEARCH_PATH);
    print("Sort comes from: %\n", sort_origin());
    print("Vendored comes from: %\n", vendored_origin());
}
