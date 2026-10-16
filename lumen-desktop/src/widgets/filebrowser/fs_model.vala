namespace LumenDesktop {

    public class FsEntry : GLib.Object {
        public GLib.File file       { get; construct; }
        public string display_name  { get; construct; }
        public bool is_dir          { get; construct; }
        public GLib.Icon? icon      { get; construct; }

        public FsEntry(GLib.File file, string display_name, bool is_dir, GLib.Icon? icon) {
            Object(file: file, display_name: display_name, is_dir: is_dir, icon: icon);
        }
    }

    public class FsModel : GLib.Object {

        private const string ATTRS =
            GLib.FileAttribute.STANDARD_NAME + "," +
            GLib.FileAttribute.STANDARD_DISPLAY_NAME + "," +
            GLib.FileAttribute.STANDARD_TYPE + "," +
            GLib.FileAttribute.STANDARD_ICON + "," +
            GLib.FileAttribute.STANDARD_IS_HIDDEN + "," +
            GLib.FileAttribute.STANDARD_IS_BACKUP;

        // Async so a slow or network mount never freezes the desktop.
        public static async GLib.List<FsEntry> list_async(GLib.File dir, bool show_hidden)
                throws GLib.Error {
            var result = new GLib.List<FsEntry>();

            var e = yield dir.enumerate_children_async(
                ATTRS, GLib.FileQueryInfoFlags.NONE, GLib.Priority.DEFAULT, null);

            while (true) {
                var batch = yield e.next_files_async(64, GLib.Priority.DEFAULT, null);
                if (batch == null || batch.length() == 0) break;

                foreach (var info in batch) {
                    if (!show_hidden && (info.get_is_hidden() || info.get_is_backup())) continue;

                    var name = info.get_display_name() ?? info.get_name();
                    bool is_dir = info.get_file_type() == GLib.FileType.DIRECTORY;
                    result.append(new FsEntry(
                        dir.get_child(info.get_name()), name, is_dir, info.get_icon()));
                }
            }

            result.sort((a, b) => {
                if (a.is_dir != b.is_dir) return a.is_dir ? -1 : 1;
                return a.display_name.collate_key_for_filename(-1)
                        .collate(b.display_name.collate_key_for_filename(-1));
            });
            return result;
        }

        public static void launch_default(GLib.File file) {
            try {
                GLib.AppInfo.launch_default_for_uri(file.get_uri(), null);
            } catch (GLib.Error err) {
                warning("lumen-desktop: cannot open %s: %s", file.get_uri(), err.message);
            }
        }
    }
}
