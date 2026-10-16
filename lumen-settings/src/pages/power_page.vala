using LumenCommon;
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

            var page = new Adw.PreferencesPage();

            var session = new Adw.PreferencesGroup() { title = "Suspend &amp; lock" };

            var lock_init = (store.get_value("power", "lock-on-suspend") ?? "true") == "true";
            var lock_row = new Adw.SwitchRow() {
                title = "Lock when suspending",
                subtitle = "Lock the screen before the system sleeps",
                active = lock_init,
            };
            lock_row.notify["active"].connect(() => {
                store.set_value("power", "lock-on-suspend", lock_row.active ? "true" : "false");
                store.save();
            });
            session.add(lock_row);

            page.add(session);

            var idle = new Adw.PreferencesGroup() { title = "Idle" };
            var dpms_init = (double) int.parse(wf.get_value("idle", "dpms_timeout") ?? "300");
            var dpms_row = new Adw.SpinRow.with_range(0, 7200, 30) {
                title = "Blank screen after",
                subtitle = "seconds of inactivity before the screen turns off (0 = never). "
                    + "Applies on next login.",
                value = dpms_init,
            };
            dpms_row.notify["value"].connect(() => {
                wf.set_value("idle", "dpms_timeout", ((int) dpms_row.value).to_string());
                wf.save();
            });
            idle.add(dpms_row);
            page.add(idle);

            return page;
        }

        // power.ini is read fresh by lumen-panel on each sleep event; Wayfire
        // [idle] changes apply on next login. No restart needed.
        public override string? restart_target() { return null; }
    }
}
