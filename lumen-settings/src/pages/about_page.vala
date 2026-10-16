namespace LumenSettings {

    public class AboutPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "about"; } }
        public string title     { owned get { return "About"; } }
        public string icon_name { owned get { return "help-about-symbolic"; } }

        public Gtk.Widget build() {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                halign = Gtk.Align.CENTER,
            };

            var title_label = new Gtk.Label("Lumen Settings") { xalign = 0.5f };
            title_label.add_css_class("lumen-about-title");
            box.append(title_label);

            var subtitle = new Gtk.Label("LumenShell session — settings front-end") {
                xalign = 0.5f,
            };
            subtitle.add_css_class("lumen-about-subtitle");
            box.append(subtitle);

            var build = new Gtk.Label("GTK4 / Vala") {
                xalign = 0.5f,
                margin_top = 12,
            };
            build.add_css_class("lumen-about-value");
            box.append(build);

            var group = new Adw.PreferencesGroup();
            group.add(box);
            var page = new Adw.PreferencesPage();
            page.add(group);
            return page;
        }
    }
}
