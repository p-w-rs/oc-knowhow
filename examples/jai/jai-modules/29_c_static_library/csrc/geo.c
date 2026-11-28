#include "geo.h"

int32_t geo_calls = 0;

int32_t geo_add(int32_t a, int32_t b) { geo_calls++; return a + b; }

Vec2 geo_scale(Vec2 v, float k) { Vec2 r = { v.x * k, v.y * k }; geo_calls++; return r; }

float geo_length_sq(const Vec2 *v) { geo_calls++; return v->x * v->x + v->y * v->y; }

size_t geo_count_char(const char *s, char c) {
    size_t n = 0;
    for (; *s; s++) if (*s == c) n++;
    geo_calls++;
    return n;
}

int64_t geo_sum(const int32_t *items, size_t n) {
    int64_t total = 0;
    for (size_t i = 0; i < n; i++) total += items[i];
    geo_calls++;
    return total;
}

int32_t geo_reduce(const int32_t *items, size_t n, geo_reducer f, void *user) {
    int32_t acc = 0;
    for (size_t i = 0; i < n; i++) acc = f(acc, items[i], user);
    geo_calls++;
    return acc;
}

const char *geo_version(void) { return "geo 1.0"; }

void geo_layout(size_t out[8]) {
    out[0] = offsetof(Record, value);        out[1] = offsetof(Record, port);        out[2] = sizeof(Record);
    out[3] = offsetof(Packed_Record, value); out[4] = offsetof(Packed_Record, port); out[5] = sizeof(Packed_Record);
    out[6] = sizeof(Vec2);                   out[7] = 0;
}

int32_t geo_record_sum(Record r)        { return r.tag + r.value + r.port; }
int32_t geo_packed_sum(Packed_Record r) { return r.tag + r.value + r.port; }
