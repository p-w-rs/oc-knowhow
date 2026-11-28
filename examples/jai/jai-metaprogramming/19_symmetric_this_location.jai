// Small compile-time helpers that show up everywhere in metaprograms:
//   #symmetric          a two-argument procedure (usually an operator) also matches with swapped args
//   #this               the enclosing procedure or struct, as a constant (anonymous recursion)
//   #procedure_name()   name of the enclosing procedure as a constant string
//   #caller_location    default value of a parameter: where the call came from
//   #location(x)        where x is declared; #file / #line / #filepath describe the current spot
// #specified on an enum forces every member to have an explicit value (safe to serialize).
// EXPECT: 3 * price = {450}, price * 3 = {450}
// EXPECT: 5! = 120 via #this
// EXPECT: inside report_here, called from 19_symmetric_this_location.jai
// EXPECT: caller line == #line at the call: true
// EXPECT: Money is declared one line above MONEY_LINE: true
// EXPECT: Opcode.HALT = 255 (enum is #specified)

#import "Basic";
#import "String";

Money :: struct { cents: s64; }
MONEY_LINE :: #line;
operator * :: (m: Money, k: s64) -> Money #symmetric { return .{m.cents * k}; }

Opcode :: enum u8 #specified { NOP :: 0; LOAD :: 1; HALT :: 255; }

factorial :: (n: int) -> int {
    if n <= 1 return 1;
    return n * #this(n - 1);
}

file_name :: (path: string) -> string {
    slash := find_index_from_right(path, #char "/");
    if slash < 0 return path;
    return slice(path, slash + 1, path.count - slash - 1);
}

report_here :: (loc := #caller_location) -> Source_Code_Location {
    print("inside %, called from %\n", #procedure_name(), file_name(loc.fully_pathed_filename));
    return loc;
}

main :: () {
    price := Money.{150};
    print("3 * price = %, price * 3 = %\n", 3 * price, price * 3);
    print("5! = % via #this\n", factorial(5));

    loc := report_here(); call_line := #line;     // both on the same line
    print("caller line == #line at the call: %\n", loc.line_number == call_line);

    where :: #location(Money);
    #assert where.line_number == MONEY_LINE - 1;
    print("Money is declared one line above MONEY_LINE: %\n", where.line_number == MONEY_LINE - 1);
    print("Opcode.HALT = % (enum is #specified)\n", cast(u8) Opcode.HALT);
}
