using LumenCommon;
using Gtk;

namespace LumenSettings {

    // Lockscreen settings — writes ~/.config/lumen-shell/lockscreen.json, which
    // lumen-lockscreen reads via its Theme loader. Restarting lumen-lockscreen
    // re-reads the file.
    public class LockscreenPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "lockscreen"; } }
        public string title     { owned get { return "Lock Screen"; } }
        public string icon_name { owned get { return "system-lock-screen-symbolic"; } }

        JsonRows rows;

        public Gtk.Widget build() {
            rows = new JsonRows(new JsonStore(Paths.lockscreen_json()));

            var page = new Adw.PreferencesPage();

            var behavior = new Adw.PreferencesGroup() { title = "Behaviour" };
            // Stored in ms, shown in seconds.
            behavior.add(rows.int_row("lockscreen.idle-timeout-ms", "Auto-lock when idle",
                0, 3600, 30, 300000, "seconds of inactivity before locking (0 = never)", 1000));
            behavior.add(rows.bool_row("lockscreen.show-power-menu", "Show power menu", true,
                "suspend / restart / shut down buttons on the lock screen"));
            page.add(behavior);

            var look = new Adw.PreferencesGroup() { title = "Appearance" };
            look.add(rows.int_row("lockscreen.blur-radius", "Backdrop blur",
                0, 64, 1, 12, "px of blur over the wallpaper backdrop"));
            look.add(rows.color_row("lockscreen.scrim", "Scrim tint",
                "#00000059", "colour tinting the blurred backdrop"));
            page.add(look);

            return page;
        }

        public override string? restart_target() { return "lumen-lockscreen"; }
    }
}
