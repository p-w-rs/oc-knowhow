// EXPECT: escapes: tab[	] hex[A] decimal[B] unicode[é] quote["] backslash[\]
// EXPECT: here-string, 2 lines, 49 bytes:
// EXPECT: path C:\temp\new "as typed" \n stays
// EXPECT: second line
// EXPECT: without the final newline: 'one line'
// EXPECT: percent sign: 50% off
// EXPECT: CRLF version has 2 carriage returns
// Escapes in ordinary string literals: \n \r \t \e \" \\ \0 \xAB \d123 \uABCD \UABCDEF12, and \% for a
// literal percent in print formats. A here-string, `#string NAME` ... `NAME` (terminator at the start of a
// line), is taken verbatim: no escapes, includes the newline before the terminator.
// `#string,cr` turns line endings into \r\n.

#import "Basic";

TEMPLATE :: #string END
path C:\temp\new "as typed" \n stays
second line
END

ONE_LINE :: #string END
one line
END

WINDOWS :: #string,cr END
a
b
END

main :: () {
    print("escapes: tab[\t] hex[\x41] decimal[\d066] unicode[\u00e9] quote[\"] backslash[\\]\n");

    lines := 0;
    for TEMPLATE  if it == #char "\n"  lines += 1;
    print("here-string, % lines, % bytes:\n%", lines, TEMPLATE.count, TEMPLATE);

    s := ONE_LINE;
    s.count -= 1;                          // drop the trailing newline the here-string always has
    print("without the final newline: '%'\n", s);

    print("percent sign: 50\% off\n");

    cr := 0;
    for WINDOWS  if it == #char "\r"  cr += 1;
    print("CRLF version has % carriage returns\n", cr);
}
