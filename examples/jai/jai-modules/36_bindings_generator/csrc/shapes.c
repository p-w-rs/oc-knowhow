#include "shapes.h"

int32_t shapes_calls = 0;

float shapes_area(Shape_Kind kind, float size) {
    shapes_calls++;
    return kind == SHAPE_SQUARE ? size * size : 3.0f * size * size;
}

float shapes_total_area(const Shape_Kind *kinds, const float *sizes, int32_t count, Shape_Area_Fn fn) {
    float total = 0;
    for (int32_t i = 0; i < count; i++) total += fn(kinds[i], sizes[i]);
    return total;
}

Shape_Point shapes_mid(Shape_Point a, Shape_Point b) {
    Shape_Point m = { (a.x + b.x) / 2, (a.y + b.y) / 2 };
    return m;
}

int32_t shapes_packed_size(void) { return (int32_t) sizeof(Shape_Packed); }
