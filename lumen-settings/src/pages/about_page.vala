using Gtk;

namespace LumenSettings {

    public class AboutPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "about"; } }
        public string title     { owned get { return "About"; } }
        public string icon_name { owned get { return "help-about-symbolic"; } }

        public Gtk.Widget build() {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 24, margin_bottom = 24,
                margin_start = 24, margin_end = 24,
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

            var info = new Gtk.Grid() {
                column_spacing = 18, row_spacing = 6,
                halign = Gtk.Align.CENTER,
                margin_top = 12,
            };
            info.attach(label_dim("Version"), 0, 0);
            info.attach(label_value(version_string()), 1, 0);
            info.attach(label_dim("Build"),   0, 1);
            info.attach(label_value("GTK4 / Vala"), 1, 1);
            box.append(info);

            var restart = new Gtk.Button.with_label("Restart Shell") {
                halign = Gtk.Align.CENTER,
                margin_top = 18,
            };
            restart.clicked.connect(() => {
                // Stubbed: a real restart would re-exec the session script.
                warning("lumen-settings: Restart Shell pressed (stub).");
                // Posix.system("pkill -HUP wayfire || true");
            });
            box.append(restart);

            return box;
        }

        static Gtk.Label label_dim(string s) {
            var l = new Gtk.Label(s) { xalign = 1 };
            l.add_css_class("lumen-about-dim");
            return l;
        }

        static Gtk.Label label_value(string s) {
            var l = new Gtk.Label(s) { xalign = 0 };
            l.add_css_class("lumen-about-value");
            return l;
        }

        static string version_string() {
            // LUMEN_SETTINGS_VERSION can be injected at build time as a
            // Vala -D define paired with a `const string` companion; until
            // that's wired, fall back to "dev".
            return "dev";
        }
    }
}
