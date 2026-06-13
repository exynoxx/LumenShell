using GLib;

[DBus(name = "org.lumenshell.OSD1")]
public class OsdService : Object {

    private OsdWindow window;
    private Presenter presenter;
    private Picker    picker;
    private uint      hide_source = 0;

    public OsdService(OsdWindow window) {
        this.window = window;
        this.presenter = new Presenter(window.pill);
        this.picker = new Picker(window);
        do_hide();
    }

    public void show(string                       kind,
                     double                       value,
                     string                       text,
                     HashTable<string, Variant>   opts) throws DBusError, IOError {

        // Don't let a transient pill (e.g. a sysfs brightness tick) clobber the
        // picker mid-pick. The commit's confirmation chip arrives after the
        // pick has ended, so it still shows.
        if (picker.active) return;

        bool    muted         = lookup_bool  (opts, "muted",      false);
        int     timeout       = lookup_int   (opts, "timeout-ms", Theme.timeout_ms);
        string? icon_override = lookup_string(opts, "icon");

        presenter.present(kind, value, text, icon_override, muted);

        window.show_pill_view();
        window.set_visible(true);
        arm_hide(timeout);
    }

    // Win+P entry point. Each <super> KEY_P binding-fire lands here: the first
    // opens the centered picker (and grabs the keyboard), each subsequent one
    // advances the highlight. Releasing Super (or clicking a tile) applies it.
    public void begin_picker() throws DBusError, IOError {
        cancel_hide();
        picker.step();
    }

    // Win+P selector. Stays up (no auto-hide) until the next show()/show_selector
    // replaces it or hide() tears it down — the wayfire-display-switch plugin
    // owns its lifetime (one call per Super+P tap, hidden on key release/apply).
    public void show_selector(string[]                     icons,
                              string[]                     labels,
                              int                          selected,
                              HashTable<string, Variant>   opts) throws DBusError, IOError {
        cancel_hide();
        window.selector.set_items(icons, labels, selected);
        window.show_selector_view();
        window.set_visible(true);
    }

    public void hide() throws DBusError, IOError {
        cancel_hide();
        do_hide();
    }

    private void do_hide() {
        window.set_visible(false);
    }

    private void cancel_hide() {
        if (hide_source != 0) {
            Source.remove(hide_source);
            hide_source = 0;
        }
    }

    private void arm_hide(int timeout_ms) {
        cancel_hide();
        if (timeout_ms <= 0) timeout_ms = Theme.timeout_ms;
        hide_source = Timeout.add(timeout_ms, () => {
            hide_source = 0;
            do_hide();
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
