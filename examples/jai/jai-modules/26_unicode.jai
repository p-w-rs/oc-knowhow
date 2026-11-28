// Strings are UTF-8 bytes: s.count and s[i] are bytes, and a plain 'for' over a
// string visits bytes. modules/Unicode decodes code points: the utf8_iter
// for_expansion (it = code point as u32, it_index = code point index), or
// utf8_next_character to consume one at a time. String's case procedures are
// ASCII-only.
// Note: write 'for :utf8_iter s' and use 'it'. Naming the variable
// ('for :utf8_iter c: s') fails with "Undeclared identifier 'it'" inside Unicode.jai
// (0.2.032), because the iterator declares 'it' itself.
// EXPECT: 20 bytes, 11 code points
// EXPECT: U+00FC at code point 2
// EXPECT: U+00DF at code point 3
// EXPECT: U+4E16 at code point 7
// EXPECT: U+754C at code point 8
// EXPECT: U+1F642 at code point 10
// EXPECT: first code point 71 (G), CONVERSION_OK, rest "rüße, 世界 🙂"
// EXPECT: plain for over "é" gives bytes: 195 169
// EXPECT: encode U+1F642: 🙂 (4 bytes)
// EXPECT: truncated sequence: U+FFFD, SOURCE_EXHAUSTED
// EXPECT: ASCII-only upper case: GRüßE

#import "Basic";
#import "Unicode";
#import "String";

hex :: (code: u32) -> string {
    digits := tprint("%", FormatInt.{value = code, base = 16, minimum_digits = 4});
    return to_upper_copy(digits,, temp);
}

main :: () {
    s := "Grüße, 世界 🙂";
    points := 0;
    for :utf8_iter s  points += 1;
    print("% bytes, % code points\n", s.count, points);

    for :utf8_iter s {
        if it > 127  print("U+% at code point %\n", hex(it), it_index);
    }

    cursor := s;
    first, result := utf8_next_character(*cursor);   // advances cursor past the code point
    ascii := cast(u8) first;
    print("first code point % (%), %, rest \"%\"\n", first, to_string(*ascii, 1), result, cursor);

    print("plain for over \"é\" gives bytes:");
    for "é"  print(" %", it);
    print("\n");

    smile := character_utf32_to_utf8(0x1F642);
    print("encode U+1F642: % (% bytes)\n", smile, smile.count);

    truncated := "é";
    code, used, status := character_utf8_to_utf32(truncated.data, 1);   // only the first of 2 bytes
    print("truncated sequence: U+%, %\n", hex(code), status);

    print("ASCII-only upper case: %\n", to_upper_copy("grüße"));
}
