// crash_handler.c — last-resort post-crash diagnostics for lumen-lockscreen.
//
// A lock daemon that vanishes mid-session leaves you blind (this happened: the
// daemon was simply gone with no journal line, no core). systemd-coredump still
// captures the core, but that needs debuginfo to read and can be disabled or
// rotated away. This handler is the always-present complement: on a fatal
// signal it appends a marker + a native backtrace to the SAME file the Vala
// DiagLog writes its lifecycle breadcrumbs to, so "what was it doing" and "where
// did it die" sit next to each other. It then re-raises with the default
// disposition so the core dump is unaffected.
//
// Everything in crash_handler() must be async-signal-safe: only write() to a
// pre-opened fd, getpid(), backtrace()/backtrace_symbols_fd(), and raise().

#define _GNU_SOURCE
#include "crash_handler.h"

#include <execinfo.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

static volatile sig_atomic_t crash_fd = -1;

// write() a string literal without strlen (sizeof - 1 drops the NUL).
#define WRITE_LIT(s) do { ssize_t _r = write(crash_fd, (s), sizeof(s) - 1); (void) _r; } while (0)

// Async-signal-safe write of a NUL-terminated string (length walked by hand;
// strlen is not on the official safe list).
static void write_cstr(const char *s) {
    int len = 0;
    while (s[len]) len++;
    ssize_t r = write(crash_fd, s, (size_t) len);
    (void) r;
}

// Async-signal-safe unsigned -> decimal.
static void write_uint(unsigned int v) {
    char buf[10];
    int i = (int) sizeof(buf);
    if (v == 0) { WRITE_LIT("0"); return; }
    while (v > 0 && i > 0) { buf[--i] = (char) ('0' + (v % 10)); v /= 10; }
    ssize_t r = write(crash_fd, &buf[i], (size_t) ((int) sizeof(buf) - i));
    (void) r;
}

static const char *sig_name(int sig) {
    switch (sig) {
        case SIGSEGV: return "SIGSEGV";
        case SIGABRT: return "SIGABRT";
        case SIGBUS:  return "SIGBUS";
        case SIGFPE:  return "SIGFPE";
        case SIGILL:  return "SIGILL";
        case SIGTRAP: return "SIGTRAP";
        default:      return "signal";
    }
}

static void crash_handler(int sig) {
    if (crash_fd >= 0) {
        WRITE_LIT("\n\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80 lumen-lockscreen FATAL ");
        write_cstr(sig_name(sig));
        WRITE_LIT(" (pid ");
        write_uint((unsigned int) getpid());
        WRITE_LIT(") \xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\n");

        void *frames[64];
        int n = backtrace(frames, 64);
        backtrace_symbols_fd(frames, n, crash_fd);
        WRITE_LIT("\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80 end backtrace \xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\n");
        fsync(crash_fd);
    }

    // Restore the default handler and re-raise so the kernel/systemd-coredump
    // still produces a core for this exact signal.
    signal(sig, SIG_DFL);
    raise(sig);
}

void crash_handler_install(const char *path) {
    crash_fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (crash_fd < 0) return;

    // Warm up backtrace() now: its first call may dlopen libgcc / malloc, which
    // is NOT safe to do from inside the signal handler.
    void *warm[1];
    (void) backtrace(warm, 1);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = crash_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS,  &sa, NULL);
    sigaction(SIGFPE,  &sa, NULL);
    sigaction(SIGILL,  &sa, NULL);
    sigaction(SIGTRAP, &sa, NULL);
}
