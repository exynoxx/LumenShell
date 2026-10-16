using LumenCommon;

namespace LumenSettings {

    public class PowerPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "power"; } }
        public string title     { owned get { return "Power"; } }
        public string icon_name { owned get { return "battery-symbolic"; } }

        IniStore store;      // power.ini (read by lumen-lockscreen)
        IniStore wf;         // wayfire.ini (idle plugin)

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
                int secs = (int) dpms_row.value;
                // Other pages write wayfire.ini too; never save a stale snapshot.
                wf.reload();
                wf.set_value("idle", "dpms_timeout", secs.to_string());
                wf.save();
#if WITH_WAYFIRE_CONFIG
                // dpms_timeout is ignored unless the idle plugin is loaded.
                if (secs > 0) Wayfire.PluginList.set_enabled(wf, "idle", true);
#endif
            });
            idle.add(dpms_row);
            page.add(idle);

            return page;
        }
    }
}
