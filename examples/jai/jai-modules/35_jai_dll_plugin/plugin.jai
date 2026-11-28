// Compiled as a dynamic library (plugin.dylib / plugin.so).

// #no_context: callable without a context (Jai calling convention otherwise).
#program_export
plugin_square :: (x: s64) -> s64 #no_context {
    return x * x;
}

// A normal Jai procedure: it receives the caller's context, but the caller's
// #Context may have a different layout (different modules, #add_context fields).
// Remap_Context() copies the members both sides share by name and size, so the
// caller's allocator, logger and print_style apply here.
#program_export
plugin_describe :: (values: [] int) -> string {
    Remap_Context();
    return sprint("plugin sees %", values);
}

#import "Basic";
#import "Remap_Context"(VERBOSE = false);   // the default VERBOSE = true logs every copied member
