#import "Basic";

// "libgreet" -> ./libgreet.dylib or ./libgreet.so, relative to this file.
// The compiler loads it while compiling: #foreign names are checked right away,
// and #run can call into it.
greet :: #library "libgreet";
greet_twice  :: (x: s32) -> s32 #foreign greet;
greet_format :: (buf: *u8, cap: s32, name: *u8) -> s32 #foreign greet;

// System libraries: found in the OS search paths (/etc/ld.so.conf on Linux).
// #library,system is the current spelling; #system_library is still accepted.
libc :: #library,system "libc";
libm :: #library,system "libm";
c_strlen :: (s: *u8) -> u64 #foreign libc "strlen";      // "name" after #foreign = the C symbol
c_sqrt   :: (x: float64) -> float64 #foreign libm "sqrt";
qsort    :: (base: *void, count: u64, size: u64, compare: (a: *void, b: *void) -> s32 #c_call) #foreign libc;
c_printf :: (format: *u8, args: ..Any) -> s32 #foreign libc "printf";  // C varargs: declare ..Any
c_fflush :: (stream: *void) -> s32 #foreign libc "fflush";

AT_COMPILE_TIME :: #run greet_twice(21);
#run print("called greet_twice(21) at compile time: %\n", AT_COMPILE_TIME);

compare_s32 :: (a: *void, b: *void) -> s32 #c_call {
    x := (cast(*s32) a).*;
    y := (cast(*s32) b).*;
    if x < y  return -1;
    if x > y  return 1;
    return 0;
}

main :: () {
    print("run time: greet_twice(5) = %\n", greet_twice(5));

    buffer: [64] u8;   // C writes into memory we own
    n := greet_format(buffer.data, buffer.count, "world");   // a literal converts to *u8
    print("greet_format wrote % bytes: %\n", n, to_string(buffer.data, n));

    print("strlen(\"four\") = %\n", c_strlen("four"));
    print("sqrt(2) from libm = %\n", c_sqrt(2));

    numbers := s32.[15, 3, -4, 8, 0];
    qsort(numbers.data, xx numbers.count, size_of(s32), compare_s32);
    print("qsort with a #c_call comparator: %\n", numbers);

    // C's stdout is buffered separately from Jai's print: flush before printing
    // from Jai again, or the C text can appear later when stdout is a pipe or file.
    c_printf("C printf: %d %.2f %s\n", 42, 3.5, "lit");
    c_fflush(null);
    print("after fflush the order is preserved\n");
}
