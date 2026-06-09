using Gtk;
using Gee;

// Left-aligned taskbar half: per-app-id buttons. Drives
// ToplevelStore subscription and pinned-apps persistence.
public class AppBar : Gtk.Box {

    HashMap<string, AppEntry> entries_by_app_id = new HashMap<string, AppEntry>();
    HashMap<uint,   AppEntry> entries_by_window = new HashMap<uint,   AppEntry>();
    string pins_file;

    public AppBar () {
        GLib.Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 2);
        add_css_class("app-row");
        halign = Gtk.Align.START;
        valign = PanelConfig.at_top ? Gtk.Align.START : Gtk.Align.END;
        hexpand = true;

        pins_file = Path.build_filename(
            Environment.get_user_config_dir(), "lumen-panel", "pinned-apps.txt");

        load_pins();

        var store = ToplevelStore.instance;
        store.added  .connect(on_added);
        store.removed.connect(on_removed);
        store.focused.connect(on_focused);
        // Replay any toplevels that were announced before we subscribed.
        foreach (unowned var t in store.all()) on_added(t);
    }

    void on_added (Toplevel t) {
        var entry = get_or_create(t.app_id);
        entry.add_window(t.id);
        entries_by_window[t.id] = entry;
        entry.queue_draw();
    }

    void on_removed (uint id) {
        if (!entries_by_window.has_key(id)) return;
        var entry = entries_by_window[id];
        entry.remove_window(id);
        entries_by_window.unset(id);
        if (!entry.is_pinned && !entry.has_open_windows()) {
            remove_entry(entry);
        }
        queue_draw();
    }

    void on_focused (uint id) {
        if (entries_by_window.has_key(id))
            entries_by_window[id].mark_focused(id);
        // Every entry's underline depends on global focus state, so repaint
        // them all — the previously-active entry needs to clear its underline.
        Gtk.Widget? w = get_first_child();
        while (w != null) {
            if (w is AppEntry) w.queue_draw();
            w = w.get_next_sibling();
        }
    }

    AppEntry get_or_create (string app_id) {
        if (entries_by_app_id.has_key(app_id)) return entries_by_app_id[app_id];

        var entry = new AppEntry(app_id, Utils.load_app_metadata(app_id));
        wire_entry(entry);
        entries_by_app_id[app_id] = entry;
        append(entry);
        return entry;
    }

    void wire_entry (AppEntry entry) {
        entry.pin_toggled.connect(() => {
            save_pins();
            // Unpinning an entry that no longer has windows means it has no
            // reason to remain in the bar — drop it immediately.
            if (!entry.is_pinned && !entry.has_open_windows())
                remove_entry(entry);
        });
        entry.unpin_and_removable.connect(() => remove_entry(entry));
    }

    void remove_entry (AppEntry entry) {
        entries_by_app_id.unset(entry.app_id);
        remove(entry);
    }

    void load_pins () {
        var pins = Ini.read_lines(pins_file);
        foreach (var app_id in pins) {
            if (app_id == "" || app_id == "--") continue;
            if (entries_by_app_id.has_key(app_id)) continue;
            var entry = new AppEntry(app_id, Utils.load_app_metadata(app_id));
            entry.is_pinned = true;
            wire_entry(entry);
            entries_by_app_id[app_id] = entry;
            append(entry);
        }
    }

    void save_pins () {
        var lst = new ArrayList<string>();
        Gtk.Widget? w = get_first_child();
        while (w != null) {
            if (w is AppEntry) {
                var e = (AppEntry) w;
                if (e.is_pinned) lst.add(e.app_id);
            }
            w = w.get_next_sibling();
        }
        Ini.write_lines(pins_file, lst);
    }
}
