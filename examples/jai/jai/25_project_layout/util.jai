// Loaded by main.jai with #load: shares the program's global scope (main.jai can call square).

square :: (x: int) -> int { return x * x; }

uses_private_helper :: () -> int { return private_helper() * 2; }

#scope_file

// Only visible inside util.jai: main.jai calling private_helper() would be "Undeclared identifier".
private_helper :: () -> int { return 5; }
