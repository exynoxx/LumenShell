using Gtk;

namespace LumenSettings {

    public class WallpaperPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "wallpaper"; } }
        public string title     { owned get { return "Wallpaper"; } }
        public string icon_name { owned get { return "preferences-desktop-wallpaper-symbolic"; } }

        IniStore store;
        const string SECTION = "wallpaper";

        public Gtk.Widget build() {
            store = new IniStore(Paths.wallpaper_ini());

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var group = new BoxedList("Background");

            var initial_image = store.get_value(SECTION, "image") ?? "";
            var file_row = new FileRow("Image", initial_image);
            file_row.value_changed.connect((p) => {
                store.set_value(SECTION, "image", p);
                store.save();
            });
            group.add_row(file_row);

            string[] labels = { "Fill", "Fit", "Center", "Stretch", "Tile" };
            string[] values = { "fill", "fit", "center", "stretch", "tile" };
            var initial_mode = store.get_value(SECTION, "mode") ?? "fill";
            var mode_row = new ComboRow("Scaling mode", labels, values, initial_mode);
            mode_row.value_changed.connect((v) => {
                store.set_value(SECTION, "mode", v);
                store.save();
            });
            group.add_row(mode_row);

            box.append(group);
            return box;
        }
    }
}
