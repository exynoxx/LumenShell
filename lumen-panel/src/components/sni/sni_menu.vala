using Gtk;
using GLib;

// DBusMenu (com.canonical.dbusmenu) client. An SNI item points at one of these
// via its Menu property; it's a separate protocol from the item itself.
//
// We fetch the whole tree in one GetLayout(0, -1, {}) call and build a
// Gtk.Popover. Activating a leaf sends Event(id, "clicked"); submenus open as
// nested popovers anchored to their row.
public class SniMenu : GLib.Object {

    const string IFACE = "com.canonical.dbusmenu";

    string bus;
    string path;
    DBusProxy? proxy = null;
    Gtk.Popover? root = null;

    public SniMenu (string bus, string path) {
        this.bus = bus;
        this.path = path;
    }

    public void show_at (Gtk.Widget anchor) {
        open.begin(anchor);
    }

    async void open (Gtk.Widget anchor) {
        try {
            proxy = yield new DBusProxy.for_bus(
                BusType.SESSION, DBusProxyFlags.NONE, null, bus, path, IFACE, null);
            // Let the app refresh its menu before we read it.
            try {
                yield proxy.call("AboutToShow", new Variant("(i)", 0),
                                 DBusCallFlags.NONE, -1, null);
            } catch (Error e) { /* optional; ignore */ }

            var reply = yield proxy.call(
                "GetLayout",
                new Variant("(iias)", 0, -1, new string[] {}),
                DBusCallFlags.NONE, -1, null);
            // reply: (u revision, (ia{sv}av) layout)
            var node = reply.get_child_value(1);

            root = new Gtk.Popover() {
                autohide = true,
                has_arrow = false,
                position = PanelConfig.at_top
                    ? Gtk.PositionType.BOTTOM : Gtk.PositionType.TOP,
            };
            root.add_css_class("systray-menu");
            root.set_child(build_box(node, root));
            root.set_parent(anchor);
            root.closed.connect(() => {
                if (root != null) { root.unparent(); root = null; }
            });
            root.popup();
        } catch (Error e) {
            warning("lumen-panel systray: menu %s%s failed: %s", bus, path, e.message);
        }
    }

    // Builds the vertical row box for one menu node's children.
    Gtk.Box build_box (Variant node, Gtk.Popover owner) {
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        box.add_css_class("systray-menu-box");

        var children = node.get_child_value(2);   // av
        size_t n = children.n_children();
        for (size_t i = 0; i < n; i++) {
            var child = children.get_child_value(i).get_variant(); // (ia{sv}av)
            add_row(box, child, owner);
        }
        return box;
    }

    void add_row (Gtk.Box box, Variant item, Gtk.Popover owner) {
        int id = item.get_child_value(0).get_int32();
        var props = new VariantDict(item.get_child_value(1));

        if (!lookup_bool(props, "visible", true)) return;

        if (lookup_string(props, "type") == "separator") {
            box.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
            return;
        }

        bool enabled = lookup_bool(props, "enabled", true);
        string label = lookup_string(props, "label") ?? "";
        bool is_submenu = lookup_string(props, "children-display") == "submenu";

        var row = new Gtk.Button() { sensitive = enabled };
        row.add_css_class("systray-menu-item");

        var content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);

        // Toggle indicator (checkbox / radio).
        string toggle = lookup_string(props, "toggle-type") ?? "";
        if (toggle != "") {
            int state = lookup_int(props, "toggle-state", 0);
            var mark = new Gtk.Image() { pixel_size = 16 };
            if (state == 1)
                mark.set_from_icon_name(toggle == "radio"
                    ? "radio-checked-symbolic" : "object-select-symbolic");
            content.append(mark);
        } else {
            string? icon = lookup_string(props, "icon-name");
            if (icon != null && icon != "") {
                var img = new Gtk.Image() { pixel_size = 16 };
                img.set_from_icon_name(icon);
                content.append(img);
            }
        }

        var lbl = new Gtk.Label(label) {
            use_underline = true,
            halign = Gtk.Align.START,
            hexpand = true,
        };
        content.append(lbl);

        if (is_submenu) {
            var arrow = new Gtk.Image() { pixel_size = 16 };
            arrow.set_from_icon_name("pan-end-symbolic");
            content.append(arrow);
        }
        row.set_child(content);

        if (is_submenu) {
            Gtk.Popover? sub = null;
            row.clicked.connect(() => {
                if (sub == null) {
                    sub = new Gtk.Popover() {
                        autohide = true,
                        has_arrow = false,
                        position = Gtk.PositionType.RIGHT,
                    };
                    sub.add_css_class("systray-menu");
                    sub.set_child(build_box(item, owner));
                    sub.set_parent(row);
                }
                sub.popup();
            });
        } else {
            row.clicked.connect(() => {
                send_event(id);
                owner.popdown();
            });
        }

        box.append(row);
    }

    void send_event (int id) {
        if (proxy == null) return;
        proxy.call.begin(
            "Event",
            new Variant("(isvu)", id, "clicked", new Variant.int32(0), (uint32) 0),
            DBusCallFlags.NONE, -1, null,
            (o, res) => {
                try { proxy.call.end(res); } catch (Error e) { /* ignore */ }
            });
    }

    static string? lookup_string (VariantDict p, string key) {
        var v = p.lookup_value(key, VariantType.STRING);
        return (v != null) ? v.get_string() : null;
    }
    static bool lookup_bool (VariantDict p, string key, bool dflt) {
        var v = p.lookup_value(key, VariantType.BOOLEAN);
        return (v != null) ? v.get_boolean() : dflt;
    }
    static int lookup_int (VariantDict p, string key, int dflt) {
        var v = p.lookup_value(key, VariantType.INT32);
        return (v != null) ? v.get_int32() : dflt;
    }
}
