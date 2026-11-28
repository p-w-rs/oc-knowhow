// A "third-party" module written before 0.2.032.
Grid :: struct {
    width, height: int;
    cells: [] float;
}

make_grid :: (width: int, height: int) -> Grid {
    g: Grid;
    g.width, g.height = width, height;
    g.cells = NewArray(width * height, float, initialized = false);   // 0.2.032: initialize = false
    return g;
}

#scope_module
#import "Basic";
