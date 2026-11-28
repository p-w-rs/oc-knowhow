// A second file of the Greeter module: it shares the module scope.
#scope_module
decorate :: (name: string) -> string {
    return tprint("%1, %2!", GREETING_WORD, name);
}

#scope_file
// Only this file can see this constant.
GREETING_WORD :: "Hello";
