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
    public string icon_name    { get; private set; default = ""; }
    public bool   is_pinned    { get; set;     default = false; }

    Gee.ArrayList<uint> window_ids = new Gee.ArrayList<uint>();
    int cycle_idx = 0;

    Gtk.Image image;
    // Resolved once in load_icon(); used to draw the dimmed back copies of the
    // stacked-icon effect for multi-window apps. The front layer stays the
    // Gtk.Image above.
    Gdk.Paintable? icon_paintable = null;
    AppPopupMenu? popup = null;

    public signal void pin_toggled ();
    public signal void unpin_and_removable ();

    public AppEntry (string app_id, AppMetadata meta) {
        GLib.Object(app_id: app_id);
        this.display_name = meta.name == "" ? app_id : meta.name;
        this.launch_cmd   = meta.launch_cmd;
        this.icon_name    = meta.icon;

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

        var rclick = new Gtk.GestureClick() { button = Gdk.BUTTON_SECONDARY };
        rclick.released.connect((n, x, y) => show_popup());
        add_controller(rclick);
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

        if (!is_pinned && window_ids.size == 0) {
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

    void show_popup () {
        if (popup == null) popup = new AppPopupMenu(this);
        popup.refresh();
        popup.popup();
    }

    // Icon names go through the default display's Gtk.IconTheme; absolute
    // paths in the .desktop file are honored directly. Falls back to the
    // bundled generic-app glyph when nothing matches.
    void load_icon () {
        if (icon_name != "") {
            if (Path.is_absolute(icon_name) && FileUtils.test(icon_name, FileTest.EXISTS)) {
                image.set_from_file(icon_name);
                try {
                    icon_paintable = Gdk.Texture.from_filename(icon_name);
                } catch (Error e) {
                    icon_paintable = null;
                }
                return;
            }
            var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
            if (theme.has_icon(icon_name)) {
                image.set_from_icon_name(icon_name);
                icon_paintable = theme.lookup_icon(
                    icon_name, null, ICON_SIZE, scale_factor,
                    Gtk.TextDirection.NONE, 0);
                return;
            }
        }
        image.set_from_resource("/dev/lumen/panel/icons/app.svg");
        icon_paintable = Gdk.Texture.from_resource("/dev/lumen/panel/icons/app.svg");
    }

    // CSS @-references don't resolve outside style rules, so the underline
    // color is hard-coded here (matches @app_active_underline in style.css).
    static Gdk.RGBA UNDERLINE_COLOR = Utils.rgba(0.0f, 0.17f, 0.9f, 1.0f);

    // Stacked-icon effect: an app with more than one window draws 2 copies of
    // its icon behind the real one, offset up-and-left, so a multi-window app
    // reads as a stack of papers at a glance.
    const int STACK_OFFSET = 4;     // px diagonal step per back layer

    public override void snapshot (Gtk.Snapshot s) {
        // Back copies first so the real Gtk.Image (front) draws on top.
        if (window_ids.size > 1 && icon_paintable != null) {
            float cx = (get_width()  - ICON_SIZE) / 2f;
            float cy = (get_height() - ICON_SIZE) / 2f;
            for (int layer = 2; layer >= 1; layer--) {   // furthest first
                var p = Graphene.Point();
                p.init(cx - STACK_OFFSET * layer, cy - STACK_OFFSET * layer);
                s.save();
                s.translate(p);
                icon_paintable.snapshot(s, ICON_SIZE, ICON_SIZE);
                s.restore();  // transform
            }
        }

        base.snapshot(s);
        if (is_active()) {
            var rect = Graphene.Rect();
            rect.init(9, get_height() - UNDERLINE_H, get_width() - 18, UNDERLINE_H);
            s.append_color(UNDERLINE_COLOR, rect);
        }
    }
}
