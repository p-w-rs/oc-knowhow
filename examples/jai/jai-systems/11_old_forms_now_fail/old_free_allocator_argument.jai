// Now: free(p,, a). free never takes the allocator as an ordinary argument.
#import "Basic";
main :: () {
    p := alloc(8);
    free(p, context.default_allocator);
}
