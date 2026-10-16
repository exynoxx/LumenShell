using Gtk;

// Available while locked by design (interactive=false: polkit authorizes the
// active session without a prompt).
public class PowerMenu : Gtk.Box {

    private LogindBridge logind;

    public PowerMenu(LogindBridge logind) {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 64);
        this.logind = logind;
        set_halign(Gtk.Align.CENTER);
        add_css_class("lockscreen-power-menu");

        append(make_button("suspend", "Suspend", () => {
            logind.suspend.begin();
        }));
        append(make_button("reboot", "Restart", () => {
            logind.reboot.begin();
        }));
        append(make_button("shutdown", "Shut Down", () => {
            logind.power_off.begin();
        }));
    }

    private delegate void Action();

    // Icons bundled in the GResource: names like system-suspend-symbolic are
    // missing from some themes (e.g. Adwaita).
    private Gtk.Widget make_button(string icon, string label_text, owned Action act) {
        var col = new Gtk.Box(Gtk.Orientation.VERTICAL, 8) {
            halign = Gtk.Align.CENTER,
        };

        var btn = new Gtk.Button() {
            tooltip_text = label_text,
            halign = Gtk.Align.CENTER,
        };
        btn.add_css_class("lockscreen-power-button");
        btn.add_css_class("circular");
        var img = new Gtk.Image() { pixel_size = 22 };
        img.set_from_resource("/org/lumenshell/lockscreen/res/" + icon + ".svg");
        btn.child = img;
        btn.clicked.connect(() => act());
        col.append(btn);

        var lbl = new Gtk.Label(label_text) {
            halign = Gtk.Align.CENTER,
        };
        lbl.add_css_class("lockscreen-power-label");
        col.append(lbl);

        return col;
    }
}
