// EXPECT: banana
// EXPECT: cherry (fell through from banana)
// EXPECT: string case: two
// EXPECT: default case: something else
// EXPECT: type case: a string type
// EXPECT: break inside a case leaves the loop: 1
// EXPECT: #complete covered every fruit: APPLE BANANA CHERRY
// `if value == { case A; ... case B; ... case; ... }` is the switch statement. Each case is its own
// scope and does NOT fall through; end a case with `#through;` to continue into the next one.
// Case values must be compile-time constants (no ranges, no duplicates); `case;` is the default.
// `if #complete e == {...}` makes a missing enum member a compile error.
// `break` inside a case leaves the enclosing loop (there is no switch-level break).

#import "Basic";

Fruit :: enum { APPLE; BANANA; CHERRY; }

name_of :: (f: Fruit) -> string {
    if #complete f == {
        case .APPLE;  return "APPLE";
        case .BANANA; return "BANANA";
        case .CHERRY; return "CHERRY";
    }
    return "?";   // still needed for control flow: a corrupted value could reach here
}

main :: () {
    f := Fruit.BANANA;
    if f == {
        case .APPLE;  print("apple\n");
        case .BANANA; print("banana\n"); #through;
        case .CHERRY; print("cherry (fell through from banana)\n");
    }

    word := "two";
    if word == {
        case "one"; print("string case: one\n");
        case "two"; print("string case: two\n");
    }

    n := 42;
    if n == {
        case 1; print("default case: one\n");
        case;   print("default case: something else\n");
    }

    T := string;
    if T == {
        case int;    print("type case: an int\n");
        case string; print("type case: a string type\n");
    }

    print("break inside a case leaves the loop:");
    for 1..3 {
        if it == {
            case 2; break;
        }
        print(" %", it);
    }
    print("\n");

    print("#complete covered every fruit: % % %\n", name_of(.APPLE), name_of(.BANANA), name_of(.CHERRY));
}
