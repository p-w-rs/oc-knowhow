// Before 0.1.096 the context's type was the global name Context (removed in 0.2.002).
// Now: #Context for the whole context, Context_Base for the fixed part (allocator, logger, ...).
#import "Basic";

save_context :: () -> Context { return context; }   // now: -> #Context
main :: () { c := save_context(); }
