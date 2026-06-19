#ifndef LUMEN_LOCKSCREEN_CRASH_HANDLER_H
#define LUMEN_LOCKSCREEN_CRASH_HANDLER_H

// Install fatal-signal handlers (SIGSEGV/SIGABRT/SIGBUS/SIGFPE/SIGILL/SIGTRAP)
// that append a marker + native backtrace to the file at `path` and then
// re-raise the signal with the default disposition (so systemd-coredump still
// gets its core). Async-signal-safe: it only write()s to a pre-opened fd and
// calls backtrace()/backtrace_symbols_fd(). Call once at startup.
void crash_handler_install(const char *path);

#endif
