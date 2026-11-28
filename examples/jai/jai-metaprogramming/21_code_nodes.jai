// Code is a first-class compile-time value. compiler_get_nodes() turns it into a syntax tree
// (root node + a flattened array of every node, children before parents); each call returns a
// FRESH copy you may edit. compiler_get_code() turns nodes back into Code for #insert, and
// Program_Print's print_expression() turns nodes back into source text.
// Here a macro rewrites every `+` in the code it receives into `*` before inserting it.
// EXPECT-COMPILE: [compile time] original:  (a + b) * 2
// EXPECT-COMPILE: [compile time] node kinds: IDENT IDENT BINARY_OPERATOR LITERAL BINARY_OPERATOR
// EXPECT-COMPILE: [compile time] rewritten: (a * b) * 2
// EXPECT: plain:     (3 + 4) * 2 = 14
// EXPECT: rewritten: (3 * 4) * 2 = 24

#import "Basic";
#import "Compiler";
#import "Program_Print";

to_text :: (node: *Code_Node) -> string {
    sb: String_Builder;
    print_expression(*sb, node);
    return builder_to_string(*sb);
}

plus_to_times :: (code: Code) -> Code {
    root, nodes := compiler_get_nodes(code);
    print("[compile time] original:  %\n", to_text(root));
    kinds: String_Builder;
    for nodes print_to_builder(*kinds, "% ", it.kind);
    print("[compile time] node kinds: %\n", builder_to_string(*kinds));
    for nodes {
        if it.kind != .BINARY_OPERATOR continue;
        op := cast(*Code_Binary_Operator) it;
        if op.operator_type == #char "+"  op.operator_type = #char "*";   // single-char operators are their ASCII value
    }
    print("[compile time] rewritten: %\n", to_text(root));
    return compiler_get_code(root, code);     // second argument: take the scope from the original
}

times_instead :: (c: Code) #expand {
    REWRITTEN :: #run plus_to_times(c);
    `result = #insert REWRITTEN;
}

main :: () {
    a := 3; b := 4;
    result: int;
    print("plain:     (3 + 4) * 2 = %\n", (a + b) * 2);
    times_instead(#code (a + b) * 2);
    print("rewritten: (3 * 4) * 2 = %\n", result);
}
