#import "Basic";
Shapes :: #import,file "shapes_bindings.jai";   // generated; its #library path is relative to that file

calls_from_c := 0;

// A Jai procedure C can call through the generated Shape_Area_Fn type.
area_callback :: (kind: Shapes.Shape_Kind, size: float) -> float #c_call {
    calls_from_c += 1;                       // globals need no context
    return Shapes.area(kind, size);
}

main :: () {
    print("MAX_POINTS = %, kinds SQUARE=% CIRCLE=%\n", Shapes.SHAPES_MAX_POINTS, cast(int) Shapes.Shape_Kind.SQUARE, cast(int) Shapes.Shape_Kind.CIRCLE);
    print("area(.SQUARE, 3) = %\n", Shapes.area(.SQUARE, 3));

    kinds := Shapes.Shape_Kind.[.CIRCLE, .SQUARE];
    sizes := float.[2, 3];
    total := Shapes.total_area(kinds.data, sizes.data, xx kinds.count, area_callback);
    print("total via a Jai callback: % (% callbacks)\n", total, calls_from_c);

    print("mid = %\n", Shapes.mid(.{1, 2}, .{3, 4}));
    print("packed struct: C says % bytes, generated Jai type has %\n", Shapes.packed_size(), size_of(Shapes.Shape_Packed));
    print("C global calls = %\n", Shapes.calls);
}
