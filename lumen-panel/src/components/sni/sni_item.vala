using Gtk;
using GLib;

// One StatusNotifierItem (one app's tray icon). Renders the icon and forwards
// pointer interaction back over D-Bus:
//   - left click   → Activate
//   - middle click → SecondaryActivate
//   - right click  → the app's DBusMenu (if any), else ContextMenu
//   - scroll       → Scroll
//
// Properties are read from a single Properties.GetAll snapshot and re-read
// whenever the item emits NewIcon/NewStatus/NewToolTip/NewTitle. We don't lean
// on GDBusProxy's cached properties because SNI signals icon changes with its
// own signals rather than PropertiesChanged, so the cache would go stale.
public class SniItem : Gtk.Button {

    const string IFACE = "org.kde.StatusNotifierItem";

    public string key { get; private set; }
    string bus;
    string path;

    Gtk.Image image;
    DBusProxy? proxy = null;
    string? menu_path = null;
    string  status = "Active";

    double scroll_acc_x = 0;
    double scroll_acc_y = 0;

    public SniItem (string bus, string path, string key) {
        this.bus = bus;
        this.path = path;
        this.key = key;

        add_css_class("tray-icon");
        add_css_class("systray-item");
        image = new Gtk.Image() { pixel_size = 22 };
        set_child(image);

        init.begin();
    }

    async void init () {
        try {
            proxy = yield new DBusProxy.for_bus(
                BusType.SESSION, DBusProxyFlags.NONE, null,
                bus, path, IFACE, null);
        } catch (Error e) {
            warning("lumen-panel systray: proxy %s%s failed: %s", bus, path, e.message);
            return;
        }

        // Re-render on any of the SNI change signals.
        proxy.g_signal.connect((sender, signal_name, parms) => {
            switch (signal_name) {
                case "NewIcon":
                case "NewOverlayIcon":
                case "NewAttentionIcon":
                case "NewStatus":
                case "NewToolTip":
                case "NewTitle":
                    refresh.begin();
                    break;
            }
        });

        wire_input();
        yield refresh();
    }

    void wire_input () {
        var click = new Gtk.GestureClick() { button = 0 };  // any button
        click.released.connect((n_press, x, y) => {
            uint b = click.get_current_button();
            if (b == Gdk.BUTTON_PRIMARY)        activate_item();
            else if (b == Gdk.BUTTON_MIDDLE)    secondary_activate();
            else if (b == Gdk.BUTTON_SECONDARY) context(x, y);
        });
        add_controller(click);

        var scroll = new Gtk.EventControllerScroll(
            Gtk.EventControllerScrollFlags.BOTH_AXES);
        scroll.scroll.connect((dx, dy) => {
            // SNI Scroll wants integer steps; GTK smooth deltas are fractional,
            // so accumulate and emit whole steps.
            scroll_acc_x += dx;
            scroll_acc_y += dy;
            int sx = (int) scroll_acc_x;
            int sy = (int) scroll_acc_y;
            if (sx != 0) { scroll_acc_x -= sx; do_scroll(sx, "horizontal"); }
            if (sy != 0) { scroll_acc_y -= sy; do_scroll(sy, "vertical"); }
            return true;
        });
        add_controller(scroll);
    }

    // --- D-Bus method forwarding --------------------------------------------

    void activate_item () {
        call_ignore("Activate", new Variant("(ii)", 0, 0));
    }
    void secondary_activate () {
        call_ignore("SecondaryActivate", new Variant("(ii)", 0, 0));
    }
    void do_scroll (int delta, string orientation) {
        call_ignore("Scroll", new Variant("(is)", delta, orientation));
    }

    void context (double x, double y) {
        if (menu_path != null) {
            var m = new SniMenu(bus, menu_path);
            m.show_at(this);
            return;
        }
        // No exported menu: ask the app to show its own context menu.
        call_ignore("ContextMenu", new Variant("(ii)", 0, 0));
    }

    void call_ignore (string method, Variant args) {
        if (proxy == null) return;
        proxy.call.begin(method, args, DBusCallFlags.NONE, -1, null, (o, res) => {
            try { proxy.call.end(res); }
            catch (Error e) { /* item went away or refused; ignore */ }
        });
    }

    // --- Property snapshot + render -----------------------------------------

    async void refresh () {
        if (proxy == null) return;
        Variant reply;
        try {
            reply = yield proxy.call(
                "org.freedesktop.DBus.Properties.GetAll",
                new Variant("(s)", IFACE),
                DBusCallFlags.NONE, -1, null);
        } catch (Error e) {
            return;
        }
        var props = new VariantDict(reply.get_child_value(0));
        apply(props);
    }

    void apply (VariantDict props) {
        // Some apps (Ayatana extension) ship icons outside the standard theme
        // dirs and point at them via IconThemePath.
        string? theme_path = lookup_string(props, "IconThemePath");
        if (theme_path != null && theme_path != "") {
            var theme = Gtk.IconTheme.get_for_display(get_display());
            bool known = false;
            foreach (var p in theme.get_search_path()) if (p == theme_path) known = true;
            if (!known) theme.add_search_path(theme_path);
        }

        status = lookup_string(props, "Status") ?? "Active";

        // Tooltip: prefer the ToolTip struct's title, fall back to Title/Id.
        string? tip = null;
        var tt = props.lookup_value("ToolTip", new VariantType("(sa(iiay)ss)"));
        if (tt != null) {
            string title = tt.get_child_value(2).get_string();
            string desc  = tt.get_child_value(3).get_string();
            tip = (desc != "") ? @"$title\n$desc" : title;
        }
        if (tip == null || tip == "") tip = lookup_string(props, "Title");
        set_tooltip_text(tip);

        // Object path of the DBusMenu, if the app exports one.
        var menu_v = props.lookup_value("Menu", VariantType.OBJECT_PATH);
        menu_path = (menu_v != null) ? menu_v.get_string() : null;

        render_icon(props);
    }

    void render_icon (VariantDict props) {
        bool attention = (status == "NeedsAttention");

        // 1) Themed icon by name (attention variant first when flagged).
        string? name = attention ? lookup_string(props, "AttentionIconName") : null;
        if (name == null || name == "") name = lookup_string(props, "IconName");
        if (name != null && name != "") {
            image.set_from_icon_name(name);
            return;
        }

        // 2) Embedded ARGB32 pixmap.
        string pix_prop = attention ? "AttentionIconPixmap" : "IconPixmap";
        var tex = best_pixmap(props, pix_prop);
        if (tex == null && attention) tex = best_pixmap(props, "IconPixmap");
        if (tex != null) {
            image.set_from_paintable(tex);
            return;
        }

        // 3) Last resort so the slot isn't blank.
        image.set_from_icon_name("application-x-executable-symbolic");
    }

    // Picks the largest pixmap and builds a texture. SNI pixmaps are ARGB32 in
    // network byte order (bytes A,R,G,B), non-premultiplied → A8R8G8B8.
    Gdk.Texture? best_pixmap (VariantDict props, string prop_name) {
        var arr = props.lookup_value(prop_name, new VariantType("a(iiay)"));
        if (arr == null) return null;

        Gdk.Texture? best = null;
        int best_w = -1;
        size_t n = arr.n_children();
        for (size_t i = 0; i < n; i++) {
            var entry = arr.get_child_value(i);
            int w = entry.get_child_value(0).get_int32();
            int h = entry.get_child_value(1).get_int32();
            if (w <= 0 || h <= 0 || w <= best_w) continue;
            var data = entry.get_child_value(2).get_data_as_bytes();
            if (data.get_size() < (size_t) (w * h * 4)) continue;
            best = new Gdk.MemoryTexture(
                w, h, Gdk.MemoryFormat.A8R8G8B8, data, w * 4);
            best_w = w;
        }
        return best;
    }

    static string? lookup_string (VariantDict props, string key) {
        var v = props.lookup_value(key, VariantType.STRING);
        return (v != null) ? v.get_string() : null;
    }
}
