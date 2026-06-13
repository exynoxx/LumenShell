using GLib;

namespace LumenSettings {

    /* Persistent diagnostic log for debugging after the process has closed or
     * crashed. Appends timestamped lines to /tmp/lumen-settings.log (mirrors the
     * wayfire-plugins `/tmp/wayfire-<name>.log` convention). Also installs a GLib
     * log writer so warning()/message()/critical()/GTK diagnostics land in the
     * same file — the things that survive a crash are exactly what you want when
     * a multi-monitor apply takes the app down.
     *
     * Tail it live while reproducing:   tail -f /tmp/lumen-settings.log
     */
    public class DiagLog {
        public const string PATH = "/tmp/lumen-settings.log";
        static bool installed = false;

        // Raw append — never throws, never recurses into GLib logging.
        public static void raw(string line) {
            var f = FileStream.open(PATH, "a");
            if (f == null) return;
            string ts;
            var now = new DateTime.now_local();
            ts = now.format("%H:%M:%S") + ".%03d".printf(now.get_microsecond() / 1000);
            f.printf("%s  %s\n", ts, line);
            f.flush();
        }

        [PrintfFormat]
        public static void log(string fmt, ...) {
            var args = va_list();
            raw(fmt.vprintf(args));
        }

        // Multi-line block with an indented header, so dumps stay readable.
        public static void block(string header, string body) {
            raw(header);
            foreach (var l in body.split("\n")) {
                if (l.strip() == "") continue;
                raw("    " + l);
            }
        }

        // Route GLib structured logs (warning/message/critical/info + GTK's own)
        // into the same file, while still printing to stderr via the default
        // writer. Call once at startup.
        public static void install() {
            if (installed) return;
            installed = true;
            raw("──────── session start ────────");
            raw("pid=%d  display=%s  desktop=%s".printf(
                (int) Posix.getpid(),
                Environment.get_variable("WAYLAND_DISPLAY") ?? "(unset)",
                Environment.get_variable("XDG_CURRENT_DESKTOP") ?? "(unset)"));

            Log.set_writer_func((level, fields) => {
                // Only persist WARNING and above — INFO/DEBUG/MESSAGE from GTK,
                // GDK (Vulkan loader), etc. would otherwise flood the file and
                // bury the display diagnostics. Our own lifecycle/apply lines
                // are written directly via DiagLog.log(), not through here.
                var sev = level & LogLevelFlags.LEVEL_MASK;
                if (sev == LogLevelFlags.LEVEL_INFO
                    || sev == LogLevelFlags.LEVEL_DEBUG
                    || sev == LogLevelFlags.LEVEL_MESSAGE)
                    return Log.writer_default(level, fields);

                string? msg = null;
                string? domain = null;
                foreach (var fld in fields) {
                    if (fld.key == "MESSAGE")
                        msg = field_string(fld);
                    else if (fld.key == "GLIB_DOMAIN")
                        domain = field_string(fld);
                }
                if (msg != null)
                    raw("[%s] %s%s".printf(level_name(level),
                        domain != null ? domain + ": " : "", msg));
                return Log.writer_default(level, fields);
            });
        }

        static string? field_string(LogField fld) {
            if (fld.length < 0)
                return (string) fld.value;            // NUL-terminated
            var sb = new StringBuilder();
            unowned uint8[] bytes = (uint8[]) fld.value;
            for (int i = 0; i < (int) fld.length; i++) sb.append_c((char) bytes[i]);
            return sb.str;
        }

        static string level_name(LogLevelFlags level) {
            if ((level & LogLevelFlags.LEVEL_ERROR)    != 0) return "ERROR";
            if ((level & LogLevelFlags.LEVEL_CRITICAL) != 0) return "CRIT";
            if ((level & LogLevelFlags.LEVEL_WARNING)  != 0) return "WARN";
            if ((level & LogLevelFlags.LEVEL_MESSAGE)  != 0) return "MSG";
            if ((level & LogLevelFlags.LEVEL_INFO)     != 0) return "INFO";
            if ((level & LogLevelFlags.LEVEL_DEBUG)    != 0) return "DEBUG";
            return "LOG";
        }
    }
}
