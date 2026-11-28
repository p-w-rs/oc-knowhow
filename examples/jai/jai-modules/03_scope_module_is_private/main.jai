// Names after #scope_module are shared inside the module but not exported:
// an importer gets "Undeclared identifier" (the compiler does not hint further).
// Fix: move the declaration under #scope_export (the default at the top of a file).
// EXPECT-COMPILE-ERROR: Undeclared identifier 'normalize_name'

#import "Basic";
#import "Accounts";

main :: () {
    print("%\n", open_account("ada"));   // fine: exported
    print("%\n", normalize_name("ada")); // error: module-private
}
