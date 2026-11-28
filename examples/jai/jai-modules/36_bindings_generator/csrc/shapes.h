/* A small C API for the bindings example (written for this example). */
#ifndef SHAPES_H
#define SHAPES_H
#include <stdint.h>

#define SHAPES_MAX_POINTS 64

/* Type names are capitalized: with strip_prefixes = "shapes_", a type called
   shapes_kind would become 'kind' and collide with parameters named 'kind'. */
typedef enum { SHAPE_CIRCLE = 1, SHAPE_SQUARE = 2 } Shape_Kind;

typedef struct { float x, y; } Shape_Point;

typedef struct __attribute__((packed)) { uint8_t kind; int32_t size; } Shape_Packed;

typedef float (*Shape_Area_Fn)(Shape_Kind kind, float size);

float shapes_area(Shape_Kind kind, float size);
float shapes_total_area(const Shape_Kind *kinds, const float *sizes, int32_t count, Shape_Area_Fn fn);
Shape_Point shapes_mid(Shape_Point a, Shape_Point b);
int32_t shapes_packed_size(void);
extern int32_t shapes_calls;
#endif
