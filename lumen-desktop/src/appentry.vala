public class AppEntry {
    public AppInfo info;
    public string display_name;
    public string short_name;
    public string name;

    public signal void launched();

    public AppEntry(AppInfo info) {
        this.info = info;
        this.display_name = info.get_display_name();
        this.short_name = display_name.char_count() > 20
            ? display_name.substring(0, 20) + "..."
            : display_name;
        this.name = display_name.ascii_down();
    }

    public void launch() {
        try {
            info.launch(null, null);
        } catch (Error e) {
            stderr.printf("Failed to launch %s: %s\n", display_name, e.message);
        }
        launched();
    }

    // Ctrl+click path: run the app as root via pkexec. pkexec triggers polkit's
    // org.freedesktop.policykit.exec action, which makes lumen-polkit-agent
    // prompt for the password. pkexec scrubs the environment for safety, so a
    // GUI child would have no display handle to connect to — we forward the
    // Wayland/X11 session vars explicitly through `env` so the elevated program
    // can actually map a window. (Some hardened apps still refuse to run as
    // root; that is the app's policy, not a launch failure on our side.)
    public void launch_as_root() {
        var cmd = info.get_commandline();
        if (cmd == null || cmd == "") {
            stderr.printf("Cannot run %s as root: no command line\n", display_name);
            launched();
            return;
        }

        try {
            string[] argv;
            Shell.parse_argv(strip_field_codes(cmd), out argv);

            string[] spawn = { "pkexec", "env" };
            foreach (var v in new string[] {
                    "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DISPLAY",
                    "XDG_CURRENT_DESKTOP", "XCURSOR_THEME", "XCURSOR_SIZE" }) {
                var val = Environment.get_variable(v);
                if (val != null && val != "") spawn += v + "=" + val;
            }
            foreach (var a in argv) spawn += a;

            Process.spawn_async(null, spawn, null,
                                SpawnFlags.SEARCH_PATH, null, null);
        } catch (Error e) {
            stderr.printf("Failed to run %s as root: %s\n", display_name, e.message);
        }
        launched();
    }

    // Strip .desktop Exec field codes (%f %F %u %U %i %c %k %d %D %n %N %v %m).
    // AppInfo.launch() expands them; a raw argv must not carry them. "%%" → "%".
    private static string strip_field_codes(string exec) {
        var sb = new StringBuilder();
        int i = 0;
        unichar c;
        bool pct = false;
        while (exec.get_next_char(ref i, out c)) {
            if (pct) {
                if (c == '%') sb.append_c('%');   // literal %% — keep one
                // otherwise drop the field-code letter entirely
                pct = false;
            } else if (c == '%') {
                pct = true;
            } else {
                sb.append_unichar(c);
            }
        }
        return sb.str.strip();
    }
}
