#ifndef STRING_EX_H
#define STRING_EX_H

#include <stdlib.h>
#include <string.h>

static char *strdup(const char *s) {
    size_t len = strlen(s) + 1;
    char *copy = (char *)malloc(len);
    if (copy) memcpy(copy, s, len);
    return copy;
}

#endif