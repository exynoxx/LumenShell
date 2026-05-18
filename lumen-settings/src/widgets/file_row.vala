using Gtk;

namespace LumenSettings {

    public class FileRow : ActionRow {
        Gtk.Button button;
        string current_path;
        public signal void value_changed(string path);

        public FileRow(string title, string initial_path, string subtitle = "") {
            base(title, subtitle);
            current_path = initial_path;
            button = new Gtk.Button.with_label(display_label(current_path));
            button.clicked.connect(open_picker);
            set_suffix(button);
        }

        public void set_path(string p) {
            current_path = p;
            button.set_label(display_label(p));
        }

        static string display_label(string p) {
            if (p == "") return "(none)";
            var basename = Path.get_basename(p);
            return basename;
        }

        void open_picker() {
            var dlg = new Gtk.FileDialog() {
                title = "Choose a file",
                modal = true,
            };
            if (current_path != "") {
                dlg.initial_file = File.new_for_path(current_path);
            }
            dlg.open.begin(
                (Gtk.Window) get_root(),
                null,
                (obj, res) => {
                    try {
                        var f = dlg.open.end(res);
                        if (f != null) {
                            var p = f.get_path();
                            if (p != null) {
                                current_path = p;
                                button.set_label(display_label(p));
                                value_changed(p);
                            }
                        }
                    } catch (Error e) { /* cancel */ }
                }
            );
        }
    }
}
