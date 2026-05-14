using GLib;

private const string USAGE =
"""Usage: lumen-osdctl <action> [args]

Actions:
  --output-volume   raise | lower | mute-toggle   [--step N]
  --input-volume    raise | lower | mute-toggle   [--step N]
  --brightness      raise | lower                 [--step N]
  --kbd-brightness  raise | lower                 [--step N]
  --caps-lock
  --custom <text>   [--value 0.5] [--icon NAME]
""";

private static bool daemon_present(DBusConnection conn) {
    try {
        var r = conn.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            new Variant("(s)", "org.lumenshell.OSD"),
            new VariantType("(b)"),
            DBusCallFlags.NONE,
            500,
            null
        );
        bool has = false;
        r.get("(b)", out has);
        return has;
    } catch (Error e) {
        return false;
    }
}

private static void send_show(string kind, double value, string text,
                              HashTable<string, Variant> opts) {
    DBusConnection conn;
    try {
        conn = Bus.get_sync(BusType.SESSION);
    } catch (Error e) {
        stderr.printf("lumen-osdctl: session bus unavailable: %s\n", e.message);
        return;
    }

    if (!daemon_present(conn)) {
        stderr.printf("lumen-osdctl: lumen-osd daemon is not running\n");
        return;
    }

    try {
        OsdProxy proxy = Bus.get_proxy_sync(
            BusType.SESSION,
            "org.lumenshell.OSD",
            "/org/lumenshell/OSD",
            DBusProxyFlags.DO_NOT_LOAD_PROPERTIES | DBusProxyFlags.DO_NOT_AUTO_START
        );
        ((DBusProxy) proxy).set_default_timeout(1500);
        proxy.show(kind, value, text, opts);
    } catch (Error e) {
        stderr.printf("lumen-osdctl: D-Bus call failed: %s\n", e.message);
    }
}

private static HashTable<string, Variant> opts_new() {
    return new HashTable<string, Variant>(str_hash, str_equal);
}

private static int parse_step(string[] args, int default_step) {
    for (int i = 0; i < args.length - 1; i++) {
        if (args[i] == "--step") {
            int n = 0;
            if (int.try_parse(args[i + 1], out n)) return n;
        }
    }
    return default_step;
}

private static string? arg_after(string[] args, string flag) {
    for (int i = 0; i < args.length - 1; i++) {
        if (args[i] == flag) return args[i + 1];
    }
    return null;
}

private static int handle_pactl_sink(string[] args) {
    if (args.length < 3) { stderr.printf(USAGE); return 1; }
    int step = parse_step(args, 5);
    Backends.State st;
    switch (args[2]) {
        case "raise":       st = Backends.output_volume_raise(step); break;
        case "lower":       st = Backends.output_volume_lower(step); break;
        case "mute-toggle": st = Backends.output_volume_mute_toggle(); break;
        default: stderr.printf(USAGE); return 1;
    }
    var opts = opts_new();
    opts.insert("muted", new Variant.boolean(st.muted));
    send_show("volume", st.value, "", opts);
    return 0;
}

private static int handle_pactl_source(string[] args) {
    if (args.length < 3) { stderr.printf(USAGE); return 1; }
    int step = parse_step(args, 5);
    Backends.State st;
    switch (args[2]) {
        case "raise":       st = Backends.input_volume_raise(step); break;
        case "lower":       st = Backends.input_volume_lower(step); break;
        case "mute-toggle": st = Backends.input_volume_mute_toggle(); break;
        default: stderr.printf(USAGE); return 1;
    }
    var opts = opts_new();
    opts.insert("muted", new Variant.boolean(st.muted));
    send_show("mic", st.value, "", opts);
    return 0;
}

private static int handle_brightness(string[] args, string kind) {
    if (args.length < 3) { stderr.printf(USAGE); return 1; }
    int step = parse_step(args, 5);
    Backends.State st;
    if (kind == "brightness") {
        switch (args[2]) {
            case "raise": st = Backends.brightness_raise(step); break;
            case "lower": st = Backends.brightness_lower(step); break;
            default: stderr.printf(USAGE); return 1;
        }
    } else {
        switch (args[2]) {
            case "raise": st = Backends.kbd_brightness_raise(step); break;
            case "lower": st = Backends.kbd_brightness_lower(step); break;
            default: stderr.printf(USAGE); return 1;
        }
    }
    send_show(kind, st.value, "", opts_new());
    return 0;
}

public static int main(string[] args) {
    if (args.length < 2) { stderr.printf(USAGE); return 1; }

    switch (args[1]) {
        case "--output-volume":
            return handle_pactl_sink(args);

        case "--input-volume":
            return handle_pactl_source(args);

        case "--brightness":
            return handle_brightness(args, "brightness");

        case "--kbd-brightness":
            return handle_brightness(args, "kbd-brightness");

        case "--caps-lock":
            bool on = Backends.caps_lock_on();
            send_show("caps-lock", 0.0, on ? "Caps ON" : "Caps OFF", opts_new());
            return 0;

        case "--custom":
            if (args.length < 3) { stderr.printf(USAGE); return 1; }
            string text = args[2];
            double value = 0.0;
            string? v_str = arg_after(args, "--value");
            if (v_str != null) double.try_parse((!) v_str, out value);
            string? icon = arg_after(args, "--icon");
            var opts = opts_new();
            if (icon != null) opts.insert("icon", new Variant.string((!) icon));
            send_show("custom", value, text, opts);
            return 0;

        case "--help":
        case "-h":
            print(USAGE);
            return 0;

        default:
            stderr.printf(USAGE);
            return 1;
    }
}
