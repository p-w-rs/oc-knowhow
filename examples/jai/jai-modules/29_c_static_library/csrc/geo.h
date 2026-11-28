/* A tiny C library used by the Jai example (written for this example). */
#ifndef GEO_H
#define GEO_H
#include <stddef.h>
#include <stdint.h>

typedef struct { float x, y; } Vec2;

/* Natural C layout: 1 + 3 padding + 4 + 2 + 2 padding = 12 bytes. */
typedef struct { uint8_t tag; int32_t value; uint16_t port; } Record;

/* Packed layout: 1 + 4 + 2 = 7 bytes. */
typedef struct __attribute__((packed)) { uint8_t tag; int32_t value; uint16_t port; } Packed_Record;

typedef int32_t (*geo_reducer)(int32_t acc, int32_t value, void *user);

int32_t     geo_add(int32_t a, int32_t b);
Vec2        geo_scale(Vec2 v, float k);              /* struct by value in and out */
float       geo_length_sq(const Vec2 *v);            /* struct by pointer */
size_t      geo_count_char(const char *s, char c);   /* NUL-terminated string */
int64_t     geo_sum(const int32_t *items, size_t n);  /* array as pointer + count */
int32_t     geo_reduce(const int32_t *items, size_t n, geo_reducer f, void *user);
const char *geo_version(void);
void        geo_layout(size_t out[8]);               /* offsets and sizes as C sees them */
int32_t     geo_record_sum(Record r);
int32_t     geo_packed_sum(Packed_Record r);

extern int32_t geo_calls;                            /* a global variable */
#endif
