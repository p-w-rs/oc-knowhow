// C wants a NUL-terminated char*; a Jai string is {count, data} with no terminator.
// Only string literals convert to *u8 automatically (their data is followed by a 0).
// For computed strings: temp_c_string(s) (temporary storage) or to_c_string(s)
// (heap, free it). Coming back: to_string(c_pointer) borrows without copying.
// EXPECT-COMPILE-ERROR: Dynamically-computed strings do not cast to *u8; only literals do.

#import "Basic";

libc :: #library,system "libc";
c_strlen :: (s: *u8) -> u64 #foreign libc "strlen";

main :: () {
    name := sprint("user%", 42);
    print("%\n", c_strlen("a literal is fine"));
    print("%\n", c_strlen(temp_c_string(name)));   // the fix
    print("%\n", c_strlen(name));                   // error: a computed string
}
