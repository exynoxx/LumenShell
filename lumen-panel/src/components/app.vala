using Gtk;
using Gee;

// One taskbar entry. Drives icon, hover, active-window underline, popover.
public class AppEntry : Gtk.Button {

    public const int SLOT_WIDTH  = 70;
    public const int SLOT_HEIGHT = 60;
    public const int UNDERLINE_H = 5;
    public const int ICON_SIZE   = 32;

    public string app_id { get; construct; }
    public string display_name { get; private set; }
    public string launch_cmd   { get; private set; default = ""; }
    public bool   is_pinned    { get; set;     default = false; }
    public bool   is_launcher  { get; construct;            }

    Gee.ArrayList<uint> window_ids = new Gee.ArrayList<uint>();
    int cycle_idx = 0;

    Gtk.Image image;
    AppPopupMenu? popup = null;

    public signal void pin_toggled ();
    public signal void unpin_and_removable ();

    public AppEntry (string app_id, string display_name, string? launch_cmd, bool is_launcher) {
        GLib.Object(app_id: app_id, is_launcher: is_launcher);
        this.display_name = display_name;
        this.launch_cmd   = launch_cmd ?? "";
        if (is_launcher) this.is_pinned = true;

        add_css_class("app-entry");
        set_size_request(SLOT_WIDTH, SLOT_HEIGHT);
        tooltip_text = display_name;

        image = new Gtk.Image() {
            pixel_size = ICON_SIZE,
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
        };
        set_child(image);
        load_icon();

        clicked.connect(on_primary_click);

        // Right-click → popover. Launcher has no popover.
        if (!is_launcher) {
            var rclick = new Gtk.GestureClick() { button = Gdk.BUTTON_SECONDARY };
            rclick.released.connect((n, x, y) => show_popup());
            add_controller(rclick);
        }
    }

    public bool has_open_windows () { return window_ids.size > 0; }

    public bool owns_window (uint id) { return window_ids.contains(id); }

    public void add_window (uint id) {
        if (!window_ids.contains(id)) window_ids.add(id);
        queue_draw();
    }

    public void remove_window (uint id) {
        var i = window_ids.index_of(id);
        if (i < 0) return;
        window_ids.remove_at(i);
        if (cycle_idx >= window_ids.size) cycle_idx = 0;
        queue_draw();

        if (!is_pinned && !is_launcher && window_ids.size == 0) {
            unpin_and_removable();
        }
    }

    public void mark_focused (uint id) {
        var i = window_ids.index_of(id);
        if (i >= 0) cycle_idx = (i + 1) % window_ids.size;
        queue_draw();
    }

    // Active iff one of our windows is the focused toplevel in ToplevelStore.
    public bool is_active () {
        foreach (var id in window_ids) {
            var t = ToplevelStore.instance.find(id);
            if (t != null && t.activated) return true;
        }
        return false;
    }

    void on_primary_click () {
        if (is_launcher) { spawn_kickoff(); return; }

        if (has_open_windows()) {
            if (cycle_idx >= window_ids.size) cycle_idx = 0;
            var id = window_ids[cycle_idx];
            cycle_idx = (cycle_idx + 1) % window_ids.size;
            ToplevelStore.instance.activate(id);
            return;
        }
        launch_new_window();
    }

    public void launch_new_window () {
        if (is_launcher) { spawn_kickoff(); return; }
        if (launch_cmd == "") {
            stderr.printf("AppEntry %s: no launch command\n", app_id);
            return;
        }
        try {
            Process.spawn_command_line_async(launch_cmd);
        } catch (Error e) {
            stderr.printf("Launch failed for %s: %s\n", app_id, e.message);
        }
    }

    public void close_all_windows () {
        var ids = new Gee.ArrayList<uint>();
        ids.add_all(window_ids);
        foreach (var id in ids) ToplevelStore.instance.close(id);
    }

    void spawn_kickoff () {
        try {
            Process.spawn_command_line_async(Utils.KICKOFF_BIN);
        } catch (Error e) {
            stderr.printf("Kickoff spawn failed: %s\n", e.message);
        }
    }

    void show_popup () {
        if (popup == null) popup = new AppPopupMenu(this);
        popup.refresh();
        popup.popup();
    }

    void load_icon () {
        if (is_launcher) {
            image.set_from_resource("/dev/lumen/panel/icons/app.svg");
            return;
        }
        var icon_path = Utils.get_icon_path_from_app_id(app_id);
        if (icon_path != null) {
            image.set_from_file(icon_path);
        } else {
            image.set_from_resource("/dev/lumen/panel/icons/app.svg");
        }
    }

    // Overlay the active-window underline. CSS can't condition on the runtime
    // set, so a 10-line snapshot override does the work.
    public override void snapshot (Gtk.Snapshot s) {
        base.snapshot(s);
        if (is_active()) {
            var color = Gdk.RGBA();
            color.parse("@app_active_underline");
            // Fallback parse — @-references don't resolve outside CSS; hard-code
            // the value to keep the lookup deterministic.
            color.red   = 0.0f;
            color.green = 0.17f;
            color.blue  = 0.9f;
            color.alpha = 1.0f;

            var rect = Graphene.Rect();
            rect.init(9, get_height() - UNDERLINE_H, get_width() - 18, UNDERLINE_H);
            s.append_color(color, rect);
        }
    }
}
