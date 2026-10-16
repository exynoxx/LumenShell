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

    // pkexec scrubs the environment, so session vars are forwarded via `env`
    // or the elevated GUI has no display to map into.
    public void launch_as_root() {
        var cmd = info.get_commandline();
        if (cmd == null || cmd == "") {
            stderr.printf("Cannot run %s as root: no command line\n", display_name);
            launched();
            return;
        }

        try {
            string[] argv;
            Shell.parse_argv(LumenCommon.strip_field_codes(cmd), out argv);

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
}
