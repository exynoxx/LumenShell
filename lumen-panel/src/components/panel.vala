using Gtk;
using Gee;

public class AppBar : Gtk.Box {

    HashMap<string, AppEntry> entries_by_app_id = new HashMap<string, AppEntry>();
    HashMap<uint,   AppEntry> entries_by_window = new HashMap<uint,   AppEntry>();
    string pins_file;

    // Drag-to-reorder state. Slots are uniform width, so reordering is a pure
    // index calculation: pitch = SLOT_WIDTH + box spacing.
    const double SLOT_PITCH = AppEntry.SLOT_WIDTH + 2;
    ArrayList<AppEntry> drag_order = new ArrayList<AppEntry>();
    AppEntry? dragged = null;
    int  drag_base_index   = 0;
    int  drag_target_index = 0;
    uint tick_id = 0;
    int64 last_frame_us = 0;

    // Per-monitor filtering. only_output is the connector this panel's monitor
    // is on (null = show every window: single-monitor, or multi-monitor with
    // per-monitor-apps off). is_tray_host is the primary panel, which also
    // catches windows whose output couldn't be resolved so they're never lost.
    string? only_output;
    bool    is_tray_host;

    public AppBar (string? only_output = null, bool is_tray_host = true) {
        GLib.Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 2);
        add_css_class("app-row");
        halign = Gtk.Align.START;
        valign = PanelConfig.at_top ? Gtk.Align.START : Gtk.Align.END;
        hexpand = true;

        this.only_output  = only_output;
        this.is_tray_host = is_tray_host;

        pins_file = Path.build_filename(
            Environment.get_user_config_dir(), "lumen-panel", "pinned-apps.txt");

        load_pins();

        var store = ToplevelStore.instance;
        store.added  .connect(on_added);
        store.removed.connect(on_removed);
        store.focused.connect(on_focused);
        store.output_changed.connect(on_output_changed);
        // Replay any toplevels that were announced before we subscribed.
        foreach (unowned var t in store.all()) on_added(t);
    }

    // Whether a window belongs on this panel's taskbar.
    bool accepts (Toplevel t) {
        if (only_output == null) return true;
        if (t.output == only_output) return true;
        // Unresolved output → only the primary panel shows it, never dropped.
        if (t.output == "" && is_tray_host) return true;
        return false;
    }

    void on_added (Toplevel t) {
        if (!accepts(t)) return;
        var entry = get_or_create(t.app_id);
        entry.add_window(t.id);
        entries_by_window[t.id] = entry;
        entry.queue_draw();
    }

    // A window moved between monitors (or its output was just resolved): add or
    // drop its taskbar membership on this panel accordingly.
    void on_output_changed (uint id, string output) {
        if (only_output == null) return;
        var t = ToplevelStore.instance.find(id);
        if (t == null) return;
        bool present = entries_by_window.has_key(id);
        bool want = accepts(t);
        if (want && !present) on_added(t);
        else if (!want && present) on_removed(id);
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

        entry.drag_started.connect(() => on_drag_started(entry));
        entry.drag_moved  .connect((ox) => on_drag_moved(ox));
        entry.drag_dropped.connect((ox) => on_drag_dropped());
    }

    // Snapshot the current AppEntry order (left-to-right) at drag start so the
    // reorder math works against a stable base while the box itself is left
    // untouched until drop.
    void on_drag_started (AppEntry entry) {
        drag_order.clear();
        Gtk.Widget? w = get_first_child();
        while (w != null) {
            if (w is AppEntry) drag_order.add((AppEntry) w);
            w = w.get_next_sibling();
        }
        dragged = entry;
        drag_base_index   = drag_order.index_of(entry);
        drag_target_index = drag_base_index;
        start_tick();
    }

    void on_drag_moved (double offset_x) {
        if (dragged == null) return;
        int n = drag_order.size;
        int delta = (int) Math.round(offset_x / SLOT_PITCH);
        int t = (drag_base_index + delta).clamp(0, n - 1);
        if (t != drag_target_index) {
            drag_target_index = t;
            recompute_targets();
        }
    }

    // Single-slot slide: entries between the dragged item's old and new slots
    // shift one pitch toward the gap it left.
    void recompute_targets () {
        int d = drag_base_index, t = drag_target_index;
        for (int i = 0; i < drag_order.size; i++) {
            var e = drag_order[i];
            if (e == dragged) continue;
            double tgt = 0;
            if (t > d && i > d && i <= t)      tgt = -SLOT_PITCH;
            else if (t < d && i >= t && i < d) tgt = +SLOT_PITCH;
            e.drag_target_x = tgt;
        }
    }

    void on_drag_dropped () {
        if (dragged == null) return;

        // Build the committed order: dragged removed, reinserted at target.
        var target_order = new ArrayList<AppEntry>();
        target_order.add_all(drag_order);
        target_order.remove(dragged);
        target_order.insert(drag_target_index, dragged);

        // Apply to the box so real child order matches.
        AppEntry? prev = null;
        foreach (var e in target_order) {
            reorder_child_after(e, prev);
            prev = e;
        }

        // Clear slide offsets on the static neighbors; let the tick ease the
        // dragged entry's residual offset back to its new slot for a snap feel.
        foreach (var e in drag_order) {
            if (e == dragged) continue;
            e.drag_offset_x = 0;
            e.drag_target_x = 0;
            e.queue_draw();
        }
        // The dragged entry's base slot is now drag_target_index; its visible
        // offset must shrink by however many slots it travelled.
        dragged.drag_offset_x -= (drag_target_index - drag_base_index) * SLOT_PITCH;
        dragged.drag_target_x = 0;

        dragged = null;
        save_pins();
    }

    void start_tick () {
        if (tick_id != 0) return;
        last_frame_us = 0;
        tick_id = add_tick_callback(animate);
    }

    // Ease every entry's drag_offset_x toward drag_target_x. Runs while a drag
    // is active or any entry is still settling after a drop.
    bool animate (Gtk.Widget w, Gdk.FrameClock clock) {
        int64 now = clock.get_frame_time();
        double dt = last_frame_us == 0 ? 0 : (now - last_frame_us) / 1000000.0;
        last_frame_us = now;
        // Exponential smoothing: ~half the gap closes every ~40ms.
        double k = dt <= 0 ? 0.35 : 1.0 - Math.exp(-dt / 0.04);

        bool busy = dragged != null;
        Gtk.Widget? c = get_first_child();
        while (c != null) {
            if (c is AppEntry) {
                var e = (AppEntry) c;
                // The lifted entry tracks the pointer directly — skip easing it
                // until it's been dropped.
                if (e != dragged) {
                    double diff = e.drag_target_x - e.drag_offset_x;
                    if (Math.fabs(diff) > 0.5) {
                        e.drag_offset_x += diff * k;
                        e.queue_draw();
                        busy = true;
                    } else if (e.drag_offset_x != e.drag_target_x) {
                        e.drag_offset_x = e.drag_target_x;
                        e.queue_draw();
                    }
                }
            }
            c = c.get_next_sibling();
        }

        if (!busy) { tick_id = 0; return Source.REMOVE; }
        return Source.CONTINUE;
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
