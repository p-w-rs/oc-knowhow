// Sorting: Sort.quick_sort sorts an array view in place (and returns it) with a
// compare procedure (negative/zero/positive), a key procedure, or (since 0.2.031)
// a user-data value passed to the compare. IntroSort.intro_sort takes (T, T) -> int.
// Basic's bubble_sort is gone (0.2.022).
// Hashing and encodings: Hash (get_hash for Hash_Table, fnv1a_hash, djb2_hash),
// Crc (crc64 = CRC-64/WE), md5, Base64, xxHash (XXH32/XXH64 in pure Jai, v0.7).
// The checksums below match independent implementations (python-xxhash, md5,
// base64 tools, a CRC-64/WE reference) and are equal on arm64 and x64.
// EXPECT: ascending [1, 2, 5, 7, 9]
// EXPECT: by age (key) [{"al", 25}, {"cy", 30}, {"bo", 35}]
// EXPECT: by name [{"al", 25}, {"bo", 35}, {"cy", 30}]
// EXPECT: descending (user data) [9, 7, 5, 2, 1]
// EXPECT: intro_sort floats [-1, 0.5, 2.5]
// EXPECT: byte order: ["Apple", "fig", "pear"]
// EXPECT: fnv1a64("hello") = 11831194018420276491
// EXPECT: crc64("123456789") = 62EC59E3F1A4F00A
// EXPECT: md5("hello") = 5d41402abc4b2a76b9719d911017c592
// EXPECT: base64 aGVsbG8sIHdvcmxk -> "hello, world" (ok true)
// EXPECT: xxh64("hello", seed 0) = 26C7827D889F6DA3

#import "Basic";
#import "Sort";
#import "IntroSort";
#import "String";
#import "Hash";
#import "Crc";
#import "md5";
#import "Base64";
XX :: #import "xxHash";

Person :: struct { name: string; age: int; }

hex :: (x: u64) -> string { return tprint("%", FormatInt.{value = x, base = 16}); }

main :: () {
    xs := int.[5, 2, 9, 1, 7];
    quick_sort(xs, (a: int, b: int) -> int { return a - b; });
    print("ascending %\n", xs);

    people := Person.[.{"cy", 30}, .{"al", 25}, .{"bo", 35}];
    quick_sort(people, (p: Person) -> int { return p.age; });
    print("by age (key) %\n", people);
    quick_sort(people, (a: Person, b: Person) -> s64 { return compare_strings(a.name, b.name); });
    print("by name %\n", people);

    descending := true;
    quick_sort(xs, descending, (a: int, b: int, desc: bool) -> int { return ifx desc then b - a else a - b; });
    print("descending (user data) %\n", xs);

    fs := float.[2.5, -1, 0.5];
    intro_sort(fs, compare_floats);
    print("intro_sort floats %\n", fs);

    words := string.["pear", "Apple", "fig"];
    quick_sort(words, compare);          // String.compare: byte order, so 'A' < 'f'
    print("byte order: %\n", words);

    hello := "hello";
    print("fnv1a64(\"hello\") = %\n", fnv1a_hash(hello.data, hello.count));
    print("crc64(\"123456789\") = %\n", to_upper_copy(hex(crc64("123456789"))));
    print("md5(\"hello\") = %\n", md5("hello"));
    encoded := base64_encode("hello, world");
    decoded, ok := base64_decode(encoded);
    print("base64 % -> \"%\" (ok %)\n", encoded, decoded, ok);
    print("xxh64(\"hello\", seed 0) = %\n", to_upper_copy(hex(XX.native_XXH64(hello.data, xx hello.count, 0))));
}
