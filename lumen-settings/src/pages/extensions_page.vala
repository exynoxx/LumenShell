using LumenCommon;

namespace LumenSettings {

    // extensions.json, kept as its parsed tree so keys we don't know survive a save.
    class ExtConfigFile : GLib.Object {
        public Json.Object root;

        public ExtConfigFile() {
            root = read_object(Paths.extensions_json()) ?? new Json.Object();
        }

        // Missing or unparsable file ⇒ null.
        public static Json.Object? read_object(string path) {
            if (!FileUtils.test(path, FileTest.EXISTS)) return null;
            try {
                var p = new Json.Parser();
                p.load_from_file(path);
                var r = p.get_root();
                if (r != null && r.get_node_type() == Json.NodeType.OBJECT) return r.get_object();
            } catch (GLib.Error e) {
                warning("lumen-settings: ignoring %s: %s", path, e.message);
            }
            return null;
        }

        // Object member `key`; created (replacing a non-object) when `create`.
        public static Json.Object? child(Json.Object o, string key, bool create) {
            var n = o.get_member(key);
            if (n != null && n.get_node_type() == Json.NodeType.OBJECT) return n.get_object();
            if (!create) return null;
            var c = new Json.Object();
            o.set_object_member(key, c);
            return c;
        }

        public bool is_enabled(string id) {
            var n = root.get_member("disabled");
            if (n == null || n.get_node_type() != Json.NodeType.ARRAY) return true;
            foreach (var e in n.get_array().get_elements())
                if (e.get_value_type() == typeof(string) && e.get_string() == id) return false;
            return true;
        }

        public void set_enabled(string id, bool on) {
            var arr = new Json.Array();
            var n = root.get_member("disabled");
            if (n != null && n.get_node_type() == Json.NodeType.ARRAY) {
                foreach (var e in n.get_array().get_elements())
                    if (!(e.get_value_type() == typeof(string) && e.get_string() == id)) arr.add_element(e.copy());
            }
            if (!on) arr.add_string_element(id);
            root.set_array_member("disabled", arr);
            save();
        }

        public void save() {
            Paths.ensure_dir();
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(root);
            var gen = new Json.Generator() { pretty = true, root = node };
            try {
                FileUtils.set_contents(Paths.extensions_json(), gen.to_data(null));  // atomic
            } catch (FileError e) {
                warning("lumen-settings: could not write %s: %s", Paths.extensions_json(), e.message);
            }
        }
    }

    // SettingsRows over params.<ext-id>.<key>, typed JSON values.
    class ParamRows : SettingsRows {
        ExtConfigFile file;
        string ext_id;

        public ParamRows(ExtConfigFile file, string ext_id) {
            this.file = file;
            this.ext_id = ext_id;
        }

        public Json.Node? get_node(string key) {
            var params = ExtConfigFile.child(file.root, "params", false);
            var o = params != null ? ExtConfigFile.child(params, ext_id, false) : null;
            return o != null ? o.get_member(key) : null;
        }

        public void put(string key, Json.Node n) {
            var o = ExtConfigFile.child(ExtConfigFile.child(file.root, "params", true), ext_id, true);
            o.set_member(key, n);
            file.save();
        }

        protected override string? read_string(string key) {
            var n = get_node(key);
            return n != null && n.get_value_type() == typeof(string) ? n.get_string() : null;
        }
        protected override void write_string(string key, string v) {
            put(key, new Json.Node(Json.NodeType.VALUE).init_string(v));
        }
        protected override int64 read_int(string key, int64 dflt) {
            var n = get_node(key);
            return n != null && n.get_value_type() == typeof(int64) ? n.get_int() : dflt;
        }
        protected override void write_int(string key, int64 v) {
            put(key, new Json.Node(Json.NodeType.VALUE).init_int(v));
        }
        protected override bool read_bool(string key, bool dflt) {
            var n = get_node(key);
            return n != null && n.get_value_type() == typeof(bool) ? n.get_boolean() : dflt;
        }
        protected override void write_bool(string key, bool v) {
            put(key, new Json.Node(Json.NodeType.VALUE).init_boolean(v));
        }
    }

    public class ExtensionsPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "extensions"; } }
        public string title     { owned get { return "Extensions"; } }
        public string icon_name { owned get { return "application-x-addon-symbolic"; } }

        const string CLASSIC = "tray-classic";

        ExtConfigFile file;
        GLib.GenericArray<Lumen.Manifest> exts;
        ComboRow presenter_row;

        public Gtk.Widget build() {
            file = new ExtConfigFile();
            exts = Lumen.Loader.discover({ Paths.extensions_dir() });
            var status = ExtConfigFile.read_object(Paths.extensions_status_json());

            var page = new Adw.PreferencesPage();

            var style = new Adw.PreferencesGroup() { title = "Tray style" };
            presenter_row = new ComboRow("Tray presenter", {}, {}, null,
                "how the tray area is drawn; extensions can provide alternatives");
            refresh_presenters();
            presenter_row.value_changed.connect((v) => {
                ExtConfigFile.child(file.root, "slots", true).set_string_member(Lumen.SLOT_TRAY_PRESENTER, v);
                file.save();
            });
            style.add(presenter_row);
            page.add(style);

            var installed = new Adw.PreferencesGroup() { title = "Installed" };
            if (exts.length == 0) {
                installed.description = "No extensions found. Put one folder per extension in %s — try copying %s".printf(
                    Paths.extensions_dir(),
                    Path.build_filename(LUMEN_DATADIR, "lumenshell", "examples", "extensions", "tray-wedge"));
            }
            foreach (var m in exts) installed.add(ext_row(m, status));
            page.add(installed);

            return page;
        }

        public override string? restart_target() { return "lumen-panel"; }

        void refresh_presenters() {
            string[] labels = { "Classic" };
            string[] values = { CLASSIC };
            foreach (var m in exts) {
                if (Lumen.SLOT_TRAY_PRESENTER in m.provides && file.is_enabled(m.id)) {
                    labels += m.name;
                    values += m.id;
                }
            }
            var slots = ExtConfigFile.child(file.root, "slots", false);
            string? current = slots != null ? slots.get_string_member_with_default(Lumen.SLOT_TRAY_PRESENTER, CLASSIC) : CLASSIC;
            presenter_row.repopulate(labels, values, current);
        }

        static string status_text(Json.Object? status, string id) {
            var s = status != null ? ExtConfigFile.child(status, id, false) : null;
            if (s == null) return "Not loaded this session";
            switch (s.get_string_member_with_default("state", "")) {
                case "loaded":   return "Loaded";
                case "disabled": return "Disabled";
                case "failed":   return "Failed: " + s.get_string_member_with_default("error", "unknown error");
                default:         return "Unknown state";
            }
        }

        Adw.ExpanderRow ext_row(Lumen.Manifest m, Json.Object? status) {
            var row = new Adw.ExpanderRow() {
                title = m.name, use_markup = false,
                subtitle = "%s · %s".printf(m.version, status_text(status, m.id)),
            };
            var sw = new Gtk.Switch() { active = file.is_enabled(m.id), valign = Gtk.Align.CENTER };
            sw.notify["active"].connect(() => {
                file.set_enabled(m.id, sw.active);
                refresh_presenters();
            });
            row.add_suffix(sw);

            var rows = new ParamRows(file, m.id);
            foreach (var p in m.parameters) row.add_row(param_row(rows, p));
            return row;
        }

        static Gtk.Widget param_row(ParamRows rows, Lumen.ParamDef p) {
            var d = p.default_value;
            bool bounded = p.min < p.max;
            switch (p.kind) {
                case Lumen.ParamType.BOOL:
                    return rows.bool_row(p.key, p.label,
                        d != null && d.get_value_type() == typeof(bool) && d.get_boolean());
                case Lumen.ParamType.INT:
                    return rows.int_row(p.key, p.label,
                        bounded ? p.min : int32.MIN, bounded ? p.max : int32.MAX, 1,
                        d != null && d.get_value_type() == typeof(int64) ? d.get_int() : 0);
                case Lumen.ParamType.DOUBLE:
                    var cur = rows.get_node(p.key) ?? d;
                    double v = cur != null && cur.get_node_type() == Json.NodeType.VALUE
                        && cur.get_value_type() != typeof(string) && cur.get_value_type() != typeof(bool)
                        ? cur.get_double() : 0;
                    var spin = SettingsRows.spin_row(p.label,
                        bounded ? p.min : -1e9, bounded ? p.max : 1e9, 0.1, v, 2);
                    spin.notify["value"].connect(() =>
                        rows.put(p.key, new Json.Node(Json.NodeType.VALUE).init_double(spin.value)));
                    return spin;
                case Lumen.ParamType.ENUM:
                    return rows.combo_row(p.key, p.label, p.choices, p.choices,
                        str_default(d) ?? (p.choices.length > 0 ? p.choices[0] : ""));
                case Lumen.ParamType.COLOR:
                    return rows.color_row(p.key, p.label, str_default(d) ?? "#ffffffff");
                default:
                    var cur = rows.get_node(p.key) ?? d;
                    var entry = new Adw.EntryRow() {
                        title = p.label,
                        text = cur != null && cur.get_value_type() == typeof(string) ? cur.get_string() : "",
                    };
                    entry.changed.connect(() =>
                        rows.put(p.key, new Json.Node(Json.NodeType.VALUE).init_string(entry.text)));
                    return entry;
            }
        }

        static string? str_default(Json.Node? d) {
            return d != null && d.get_value_type() == typeof(string) ? d.get_string() : null;
        }
    }
}
