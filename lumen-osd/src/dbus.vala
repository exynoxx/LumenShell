using GLib;

[DBus(name = "org.lumenshell.OSD1")]
public class OsdService : Object {

    private OsdWindow window;
    private Presenter presenter;
    private uint      hide_source = 0;

    public OsdService(OsdWindow window) {
        this.window = window;
        this.presenter = new Presenter(window.pill);
        hide();
    }

    public void show(string                       kind,
                     double                       value,
                     string                       text,
                     HashTable<string, Variant>   opts) throws DBusError, IOError {

        bool    muted         = lookup_bool  (opts, "muted",      false);
        int     timeout       = lookup_int   (opts, "timeout-ms", Theme.timeout_ms);
        string? icon_override = lookup_string(opts, "icon");

        presenter.present(kind, value, text, icon_override, muted);

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
