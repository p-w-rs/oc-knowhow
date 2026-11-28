// A for_expansion should reject flags it cannot honor at compile time instead of silently
// ignoring them. Here the user asks for reverse iteration of a forward-only stream.
// EXPECT-COMPILE-ERROR: Compile-time assertion failed. "Lines can only be iterated forward"
// EXPECT-COMPILE-ERROR: While expanding macro 'for_expansion' here...

#import "Basic";

Lines :: struct { text: string; }

for_expansion :: (l: Lines, body: Code, flags: For_Flags) #expand {
    #assert !(flags & .REVERSE) "Lines can only be iterated forward";
    start, n := 0, 0;
    for i: 0..l.text.count {
        if i < l.text.count && l.text[i] != #char "\n" continue;
        `it := slice(l.text, start, i - start);
        `it_index := n;
        start, n = i + 1, n + 1;
        #insert body;
    }
}

main :: () {
    for < Lines.{"a\nb"}  print("%\n", it);
}
#import "String";
