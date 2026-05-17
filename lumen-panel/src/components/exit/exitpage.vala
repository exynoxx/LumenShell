using Gtk;

// ExitPage — three round action buttons offering session-end choices:
// Log Out (terminates the compositor → returns to the login manager),
// Reboot, and Shutdown. Mirrors the structural pattern of the other
// expandable tray pages (Battery / WiFi / Sound).
public class ExitPage : Gtk.Box {

    const int PAD = 14;

    public ExitPage () {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class("exit-page");
        set_size_request(380, 200);

        var title = new Gtk.Label("Session") {
            xalign = 0,
            margin_start = PAD,
            margin_top = PAD,
            margin_bottom = 6,
        };
        title.add_css_class("page-title");
        append(title);

        var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 24) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
            hexpand = true,
            vexpand = true,
            margin_bottom = PAD,
        };

        row.append(make_action("logout",   "Log Out",  "pkill wayfire"));
        row.append(make_action("reboot",   "Reboot",   "systemctl reboot"));
        row.append(make_action("shutdown", "Shutdown", "systemctl poweroff"));

        append(row);
    }

    Gtk.Widget make_action (string icon_name, string label_text, string cmd) {
        var col = new Gtk.Box(Gtk.Orientation.VERTICAL, 8) {
            halign = Gtk.Align.CENTER,
        };

        var btn = new Gtk.Button() {
            halign = Gtk.Align.CENTER,
        };
        btn.add_css_class("exit-action");
        var img = new Gtk.Image() {
            pixel_size = 28,
        };
        img.set_from_resource("/dev/lumen/panel/icons/" + icon_name + ".svg");
        btn.set_child(img);
        btn.clicked.connect(() => {
            try { Process.spawn_command_line_async(cmd); }
            catch (SpawnError e) { warning("Exit action '%s' failed: %s", cmd, e.message); }
        });
        col.append(btn);

        var lbl = new Gtk.Label(label_text) {
            halign = Gtk.Align.CENTER,
        };
        lbl.add_css_class("exit-action-label");
        col.append(lbl);

        return col;
    }
}
