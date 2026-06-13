using Gtk;

namespace LumenSettings {

    public class PowerPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "power"; } }
        public string title     { owned get { return "Power"; } }
        public string icon_name { owned get { return "battery-symbolic"; } }

        IniStore store;      // ~/.config/lumen-shell/power.ini  (read by lumen-panel)
        IniStore wf;         // ~/.config/wayfire.ini            (Wayfire idle plugin)

        public Gtk.Widget build() {
            store = new IniStore(Paths.power_ini());
            wf    = new IniStore(Paths.wayfire_ini());

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var session = new BoxedList("Suspend & lock");

            var lock_init = (store.get_value("power", "lock-on-suspend") ?? "true") == "true";
            var lock_row = new SwitchRow("Lock when suspending",
                "Lock the screen before the system sleeps", lock_init);
            lock_row.toggled.connect((v) => {
                store.set_value("power", "lock-on-suspend", v ? "true" : "false");
                store.save();
            });
            session.add_row(lock_row);

            string[] lid_labels = { "Suspend", "Lock only", "Do nothing" };
            string[] lid_values = { "suspend", "lock-only", "nothing" };
            var lid_init = store.get_value("power", "lid.action") ?? "suspend";
            var lid_row = new ComboRow("When the lid closes", lid_labels, lid_values,
                lid_init,
                "What LumenShell does on lid close. Changing whether the system itself "
                + "suspends requires editing /etc/systemd/logind.conf.");
            lid_row.value_changed.connect((v) => {
                store.set_value("power", "lid.action", v);
                store.save();
            });
            session.add_row(lid_row);
            box.append(session);

            var idle = new BoxedList("Idle");
            var dpms_init = (double) int.parse(wf.get_value("idle", "dpms_timeout") ?? "300");
            var dpms_row = new SpinRow("Blank screen after", 0, 7200, 30, dpms_init, 0,
                "seconds of inactivity before the screen turns off (0 = never). "
                + "Applies on next login.");
            dpms_row.value_changed.connect((v) => {
                wf.set_value("idle", "dpms_timeout", ((int) v).to_string());
                wf.save();
            });
            idle.add_row(dpms_row);
            box.append(idle);

            return box;
        }

        // power.ini is read fresh by lumen-panel on each sleep event; Wayfire
        // [idle] changes apply on next login. No restart needed.
        public override string? restart_target() { return null; }
    }
}
