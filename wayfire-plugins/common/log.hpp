#pragma once

// Append-only debug log shared by the plugins: one timestamped line per call to
// /tmp/wayfire-<name>.log, for correlating with the Vala side. Truncate the file
// manually before a test session.

#include <cstdarg>
#include <cstdio>
#include <ctime>

namespace lumen
{
inline void file_log(const char *path, const char *fmt, ...)
{
    FILE *fp = std::fopen(path, "a");
    if (!fp)
    {
        return;
    }

    timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    std::fprintf(fp, "[%ld.%03ld] ", (long) ts.tv_sec, (long) (ts.tv_nsec / 1000000));

    va_list ap;
    va_start(ap, fmt);
    std::vfprintf(fp, fmt, ap);
    va_end(ap);

    std::fputc('\n', fp);
    std::fclose(fp);
}
}
