namespace LumenSettings {

    // KEEP_COMMENTS round-trips comments and ordering; KeyFile only rewrites
    // `key = value` as `key=value`, which Wayfire accepts.
    public class IniStore : GLib.Object {
        public string path { get; construct; }

        const KeyFileFlags FLAGS =
            KeyFileFlags.KEEP_COMMENTS | KeyFileFlags.KEEP_TRANSLATIONS;

        KeyFile kf = new KeyFile();

        // False when even the normalised file won't parse; save() then refuses,
        // since KeyFile would write back only the fragment it read.
        bool writable = true;

        public IniStore(string path) {
            Object(path: path);
            load();
        }

        public void reload() {
            load();
        }

        // Wayfire's parser treats an unescaped `#` anywhere as a comment, so a
        // colour like #242424FF must be stored as \#242424FF. KeyFile readers
        // of our own INIs would choke on the escape, hence wayfire.ini only.
        bool wayfire_escapes { get { return path == LumenCommon.Paths.wayfire_ini(); } }

        public string? get_value(string section, string key) {
            try {
                var v = kf.get_value(section, key);
                return wayfire_escapes ? v.replace("\\#", "#") : v;
            } catch (KeyFileError e) {
                return null;
            }
        }

        public Gee.ArrayList<string> sections() {
            var result = new Gee.ArrayList<string>();
            foreach (var g in kf.get_groups()) result.add(g);
            return result;
        }

        public Gee.ArrayList<string> keys_in(string section) {
            var result = new Gee.ArrayList<string>();
            try {
                foreach (var k in kf.get_keys(section)) result.add(k);
            } catch (KeyFileError e) {
                // Missing section — no keys.
            }
            return result;
        }

        public void set_value(string section, string key, string value) {
            kf.set_value(section, key,
                         wayfire_escapes ? value.replace("\\#", "#").replace("#", "\\#") : value);
        }

        public void remove_key(string section, string key) {
            try {
                kf.remove_key(section, key);
            } catch (KeyFileError e) {
                // Already absent.
            }
        }

        public void save() {
            if (!writable) {
                warning("IniStore: refusing to overwrite unparseable %s", path);
                return;
            }
            if (DirUtils.create_with_parents(Path.get_dirname(path), 0755) != 0) {
                warning("IniStore: cannot create directory for %s", path);
                return;
            }
            try {
                kf.save_to_file(path);
            } catch (FileError e) {
                warning("IniStore: write %s: %s", path, e.message);
            }
        }

        void load() {
            kf = new KeyFile();
            writable = true;
            if (!FileUtils.test(path, FileTest.EXISTS)) return;

            try {
                kf.load_from_file(path, FLAGS);
                return;
            } catch (Error e) {
                // Fall through: retry on a normalised copy.
            }

            string content;
            try {
                FileUtils.get_contents(path, out content);
            } catch (FileError e) {
                warning("IniStore: read %s: %s", path, e.message);
                writable = false;
                return;
            }

            try {
                kf = new KeyFile();
                kf.load_from_data(normalize(content), -1, FLAGS);
            } catch (KeyFileError e) {
                warning("IniStore: %s is not parseable (%s); it will be read as "
                        + "empty and left untouched", path, e.message);
                kf = new KeyFile();
                writable = false;
            }
        }

        // KeyFile rejects ';' comments, non-`key=value` lines and keys before the
        // first group; '#'-comment them so the rest loads and survives a save.
        static string normalize(string content) {
            var sb = new StringBuilder();
            bool in_group = false;
            foreach (var line in content.split("\n")) {
                var t = line.strip();
                bool ok = t == ""
                    || t.has_prefix("#")
                    || (t.has_prefix("[") && t.has_suffix("]"))
                    || (in_group && t.index_of_char('=') > 0);
                sb.append(ok ? line : "#" + line);
                sb.append_c('\n');
                if (t.has_prefix("[")) in_group = true;
            }
            return sb.str;
        }
    }
}
