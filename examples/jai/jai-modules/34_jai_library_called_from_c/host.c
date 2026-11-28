/* A C program calling the Jai static library (written for this example). */
#include <stdio.h>
#include "stats.h"

int main(int argc, char **argv) {
    /* Set up the Jai runtime (context, temporary storage) before calling Jai. */
    struct Context0 *ctx = __jai_runtime_init(argc, (u8 **) argv);
    double values[] = { 1.0, 2.0, 6.0 };
    Stats s = jai_stats(values, 3);
    printf("C got: add=%d count=%lld mean=%.2f\n", jai_add(2, 40), (long long) s.count, s.mean);
    printf("C got: %s\n", (const char *) jai_greeting((u8 *) "C"));
    __jai_runtime_fini(ctx);
    return 0;
}
