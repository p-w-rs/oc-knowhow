// A module with parameters. The first list holds MODULE parameters (each #import may choose its
// own values; different values = a separate copy of the module). The optional second list holds
// PROGRAM parameters (set once for the whole program, shared by every import).
// Parameters are compile-time constants inside the module and are not visible to importers.
#module_parameters (GREETING := "hello", LOUD := false) (LOG_CALLS := false);

#assert is_constant(LOUD);

greet :: (name: string) {
    calls += 1;
    #if LOUD  print("%, %!!!\n", to_upper_copy(GREETING), name);
    else      print("%, %.\n", GREETING, name);
    #if LOG_CALLS  print("  [Greeter(%)] call #%\n", GREETING, calls);
}

calls: int;     // every distinct import of the module gets its own copy

#scope_module
#import "Basic";
#import "String";
