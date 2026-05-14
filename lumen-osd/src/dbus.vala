[DBus(name = "org.lumenshell.OSD1")]
public class OsdService : Object {

    private OsdWindow window;
    private uint      hide_source = 0;

    public OsdService(OsdWindow window) {
        this.window = window;
        hide();
    }

    public void show(string                       kind,
                     double                       value,
                     string                       text,
                     HashTable<string, Variant>   opts) throws DBusError, IOError {

        bool muted    = lookup_bool(opts, "muted", false);
        int  timeout  = lookup_int (opts, "timeout-ms", Theme.timeout_ms);
        string? icon_override = lookup_string(opts, "icon");

        string icon = (icon_override != null)
                      ? (!) icon_override
                      : icon_for(kind, value, muted);

        switch (kind) {
            case "volume":
            case "mic":
            case "brightness":
            case "kbd-brightness":
                window.pill.show_slider(icon, value,
                    text != "" ? text : "%d%%".printf((int) Math.round(value * 100)));
                break;

            case "caps-lock":
                window.pill.show_chip(icon, text != "" ? text : "Caps");
                break;

            case "custom":
            default:
                if (text != "" && value <= 0.0) {
                    window.pill.show_chip(icon, text);
                } else if (value > 0.0) {
                    window.pill.show_slider(icon, value, text);
                } else {
                    window.pill.show_chip(icon, kind);
                }
                break;
        }

        window.set_visible(true);
        arm_hide(timeout);
    }

    private void hide() {
        window.set_visible(false);
    }

    private void arm_hide(int timeout_ms) {
        if (hide_source != 0) {
            Source.remove(hide_source);
            hide_source = 0;
        }
        if (timeout_ms <= 0) timeout_ms = Theme.timeout_ms;
        hide_source = Timeout.add(timeout_ms, () => {
            hide_source = 0;
            hide();
            return Source.REMOVE;
        });
    }

    private string icon_for(string kind, double value, bool muted) {
        switch (kind) {
            case "volume":
                if (muted) return "audio-volume-muted-symbolic";
                if (value <= 0.01) return "audio-volume-muted-symbolic";
                if (value < 0.34)  return "audio-volume-low-symbolic";
                if (value < 0.67)  return "audio-volume-medium-symbolic";
                return "audio-volume-high-symbolic";
            case "mic":
                if (muted) return "microphone-sensitivity-muted-symbolic";
                if (value < 0.34) return "microphone-sensitivity-low-symbolic";
                if (value < 0.67) return "microphone-sensitivity-medium-symbolic";
                return "microphone-sensitivity-high-symbolic";
            case "brightness":
                return "display-brightness-symbolic";
            case "kbd-brightness":
                return "keyboard-brightness-symbolic";
            case "caps-lock":
                return "keyboard-symbolic";
            case "custom":
            default:
                return "dialog-information-symbolic";
        }
    }

    private static bool lookup_bool(HashTable<string, Variant> opts,
                                    string key, bool fallback) {
        var v = opts.lookup(key);
        if (v == null || !v.is_of_type(VariantType.BOOLEAN)) return fallback;
        return v.get_boolean();
    }

    private static int lookup_int(HashTable<string, Variant> opts,
                                  string key, int fallback) {
        var v = opts.lookup(key);
        if (v == null) return fallback;
        if (v.is_of_type(VariantType.INT32))  return v.get_int32();
        if (v.is_of_type(VariantType.UINT32)) return (int) v.get_uint32();
        if (v.is_of_type(VariantType.INT64))  return (int) v.get_int64();
        return fallback;
    }

    private static string? lookup_string(HashTable<string, Variant> opts,
                                         string key) {
        var v = opts.lookup(key);
        if (v == null || !v.is_of_type(VariantType.STRING)) return null;
        return v.get_string();
    }
}
