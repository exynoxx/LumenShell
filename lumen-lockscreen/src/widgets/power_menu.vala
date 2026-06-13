using Gtk;

// Suspend / Restart / Shutdown row. Thin consumer of the shared
// lumen-common/logind.vala LogindBridge (interactive=false; polkit authorizes
// for the active session, no prompt). Hidden entirely when the theme disables
// it. These actions remain available while locked by design — same as every
// mainstream lock screen.
public class PowerMenu : Gtk.Box {

    private LogindBridge logind;

    public PowerMenu(LogindBridge logind) {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 18);
        this.logind = logind;
        set_halign(Gtk.Align.CENTER);
        add_css_class("lockscreen-power-menu");

        append(make_button("system-suspend-symbolic", "Suspend", () => {
            logind.suspend.begin();
        }));
        append(make_button("system-reboot-symbolic", "Restart", () => {
            logind.reboot.begin();
        }));
        append(make_button("system-shutdown-symbolic", "Shut Down", () => {
            logind.power_off.begin();
        }));
    }

    private delegate void Action();

    private Gtk.Button make_button(string icon, string tooltip, owned Action act) {
        var btn = new Gtk.Button() {
            tooltip_text = tooltip,
            valign = Gtk.Align.CENTER,
        };
        btn.add_css_class("lockscreen-power-button");
        btn.add_css_class("circular");
        btn.child = new Gtk.Image.from_icon_name(icon) { pixel_size = 22 };
        btn.clicked.connect(() => act());
        return btn;
    }
}
