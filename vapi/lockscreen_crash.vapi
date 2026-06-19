// Bindings for lumen-lockscreen/src/crash_handler.c — fatal-signal backtrace
// dumper. Mirrors the pam_auth.vapi hand-written-binding pattern.
[CCode (cheader_filename = "crash_handler.h")]
namespace CrashHandler {
    [CCode (cname = "crash_handler_install")]
    public void install (string path);
}
