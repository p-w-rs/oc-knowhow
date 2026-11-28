// False friend from C/C++: static_assert(cond, "msg"). In Jai the message follows the condition
// without a comma; the parenthesized comma form does not parse.
// Right:  #assert size_of(Header) == 8 "Header layout changed";
// EXPECT-COMPILE-ERROR: Comma-separated expressions in an impermissible place

Header :: struct { a: u32; b: u32; }

#assert(size_of(Header) == 8, "Header layout changed");

main :: () {}
