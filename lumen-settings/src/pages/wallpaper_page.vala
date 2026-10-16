using LumenCommon;

namespace LumenSettings {

    public class WallpaperPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "wallpaper"; } }
        public string title     { owned get { return "Wallpaper"; } }
        public string icon_name { owned get { return "preferences-desktop-wallpaper-symbolic"; } }

        IniStore store;
        const string SECTION = "wallpaper";

        public Gtk.Widget build() {
            store = new IniStore(Paths.wallpaper_ini());

            var page = new Adw.PreferencesPage();

            var group = new Adw.PreferencesGroup() { title = "Background" };

            var initial_image = store.get_value(SECTION, "image") ?? "";
            var file_row = new FileRow("Image", initial_image, "background image file");
            file_row.value_changed.connect((p) => {
                store.set_value(SECTION, "image", p);
                store.save();
                // The desktop itself is drawn by wf-background, which reads
                // wf-shell.ini and reloads it live; wallpaper.ini only reaches
                // the lock screen.
                var wf_shell = new IniStore(LumenCommon.Paths.wf_shell_ini());
                wf_shell.set_value("background", "image", p);
                wf_shell.save();
            });
            group.add(file_row);

            page.add(group);
            return page;
        }
    }
}
