/* A small shared library for the Jai example (written for this example). */
#include <stdio.h>
#include <string.h>

int greet_twice(int x) { return 2 * x; }

/* Writes "hello, <name>" into buf (C owns nothing; the caller provides memory). */
int greet_format(char *buf, int cap, const char *name) {
    return snprintf(buf, (size_t) cap, "hello, %s", name);
}
