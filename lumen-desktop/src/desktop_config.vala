namespace LumenDesktop {

    public class WidgetPosition : GLib.Object {
        public int x;
        public int y;
        public WidgetPosition(int x, int y) { this.x = x; this.y = y; }
    }

    // x/y are the fallback for a monitor with no `positions` entry.
    public class WidgetSpec : GLib.Object {
        public string type_name  { get; set; default = "file-browser"; }
        public string shape_name { get; set; default = "folder"; }
        public double radius     { get; set; default = 22.0; }
        public int width         { get; set; default = 630; }
        public int height        { get; set; default = 364; }
        public int x             { get; set; default = -1; }   // -1 = centre
        public int y             { get; set; default = -1; }

        // tab_ratio is a fraction of the widget width.
        public double border_width { get; set; default = 5.0; }
        public double tab_height   { get; set; default = 26.0; }
        public double tab_ratio    { get; set; default = 0.34; }
        public string border_color { get; set; default = "#ffffff"; }
        public WidgetSettings settings { get; set; default = new WidgetSettings(); }

        // Index in the file's "widgets" array: the write-back handle.
        public int index { get; set; default = -1; }

        // Keyed by connector name; each monitor's copy is dragged independently.
        public GLib.HashTable<string, WidgetPosition> positions
            = new GLib.HashTable<string, WidgetPosition>(str_hash, str_equal);

        public void resolve_position(string monitor, out int px, out int py) {
            var p = positions.lookup(monitor);
            if (p != null) {
                px = p.x;
                py = p.y;
                return;
            }
            px = x;
            py = y;
        }

        public void set_position(string monitor, int px, int py) {
            positions.insert(monitor, new WidgetPosition(px, py));
        }

        public WidgetShape make_shape() {
            return WidgetShape.from_spec(shape_name, radius, tab_height, tab_ratio);
        }
    }

    public class DesktopConfig : GLib.Object {

        public static WidgetSpec[] widgets = {};

        public static string config_path() {
            return LumenCommon.Paths.desktop_json();
        }

        public static void load() {
            var path = config_path();
            if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
                widgets = { new WidgetSpec() };
                reindex();
                return;
            }

            bool had_list = false;
            try {
                var parser = new Json.Parser();
                parser.load_from_file(path);
                widgets = parse_root(parser.get_root(), out had_list);
            } catch (GLib.Error e) {
                warning("lumen-desktop: reading %s: %s", path, e.message);
                widgets = { new WidgetSpec() };
                reindex();
                return;
            }

            // Only a *missing* list falls back to the default. An empty one is
            // what removing the last widget leaves behind, and must stick.
            if (widgets.length == 0 && !had_list) {
                warning("lumen-desktop: %s has no widgets, using the default", path);
                widgets = { new WidgetSpec() };
            }
            reindex();
        }

        private static void reindex() {
            for (int i = 0; i < widgets.length; i++) widgets[i].index = i;
        }

        private static WidgetSpec[] parse_root(Json.Node? root, out bool had_list) {
            WidgetSpec[] result = {};
            had_list = false;
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return result;

            var obj = root.get_object();
            if (!obj.has_member("widgets")) return result;

            var member = obj.get_member("widgets");
            if (member.get_node_type() != Json.NodeType.ARRAY) return result;
            had_list = true;

            var arr = member.get_array();
            for (uint i = 0; i < arr.get_length(); i++) {
                var node = arr.get_element(i);
                if (node.get_node_type() != Json.NodeType.OBJECT) continue;
                result += parse_widget(node.get_object());
            }
            return result;
        }

        private static WidgetSpec parse_widget(Json.Object o) {
            var spec = new WidgetSpec();
            if (o.has_member("type"))   spec.type_name  = o.get_string_member("type");
            if (o.has_member("shape"))  spec.shape_name = o.get_string_member("shape");
            if (o.has_member("radius")) spec.radius     = o.get_double_member("radius");
            if (o.has_member("width"))  spec.width      = (int) o.get_int_member("width");
            if (o.has_member("height")) spec.height     = (int) o.get_int_member("height");
            if (o.has_member("x"))      spec.x          = (int) o.get_int_member("x");
            if (o.has_member("y"))      spec.y          = (int) o.get_int_member("y");

            if (o.has_member("border-width"))
                spec.border_width = o.get_double_member("border-width");
            if (o.has_member("tab-height"))
                spec.tab_height = o.get_double_member("tab-height");
            if (o.has_member("tab-width"))
                spec.tab_ratio = o.get_double_member("tab-width");
            if (o.has_member("border-color"))
                spec.border_color = o.get_string_member("border-color");

            if (o.has_member("positions")) {
                var pn = o.get_member("positions");
                if (pn.get_node_type() == Json.NodeType.OBJECT) {
                    var po = pn.get_object();
                    foreach (var key in po.get_members()) {
                        var en = po.get_member(key);
                        if (en.get_node_type() != Json.NodeType.OBJECT) continue;
                        var eo = en.get_object();
                        if (!eo.has_member("x") || !eo.has_member("y")) continue;
                        spec.set_position(key, (int) eo.get_int_member("x"),
                                               (int) eo.get_int_member("y"));
                    }
                }
            }

            if (o.has_member("settings")) {
                var sn = o.get_member("settings");
                if (sn.get_node_type() == Json.NodeType.OBJECT) {
                    var so = sn.get_object();
                    foreach (var key in so.get_members()) {
                        var v = scalar_to_string(so.get_member(key));
                        if (v != null) spec.settings.put(key, v);
                    }
                }
            }
            return spec;
        }

        // In-memory spec updated first so a second drag before reload starts
        // from the right place.
        public static void save_position(WidgetSpec spec, string monitor,
                                         int px, int py) {
            spec.set_position(monitor, px, py);

            var root = document();
            var entry = widget_entry(root, spec);
            if (entry == null) return;
            write_positions(entry, spec);
            write(root);
        }

        // Callers must reload afterwards: later indices have shifted.
        public static void remove_widget(WidgetSpec spec) {
            var root = document();
            var arr = root.get_object().get_array_member("widgets");
            if (spec.index < 0 || spec.index >= arr.get_length()) {
                warning("lumen-desktop: cannot remove widget %d of %u",
                    spec.index, arr.get_length());
                return;
            }
            arr.remove_element((uint) spec.index);
            write(root);
        }

        // Patch the on-disk tree so unknown keys and widget types survive; a
        // widget-count mismatch means it was edited under us, so use the model.
        private static Json.Node document() {
            var path = config_path();
            if (GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
                try {
                    var parser = new Json.Parser();
                    parser.load_from_file(path);
                    var root = parser.get_root();
                    if (root != null && root.get_node_type() == Json.NodeType.OBJECT
                        && root.get_object().has_member("widgets")) {
                        var m = root.get_object().get_member("widgets");
                        if (m.get_node_type() == Json.NodeType.ARRAY
                            && m.get_array().get_length() == widgets.length) {
                            return root.copy();
                        }
                    }
                } catch (GLib.Error e) {
                    warning("lumen-desktop: re-reading %s: %s", path, e.message);
                }
            }
            return generate();
        }

        private static Json.Object? widget_entry(Json.Node root, WidgetSpec spec) {
            var arr = root.get_object().get_array_member("widgets");
            if (spec.index < 0 || spec.index >= arr.get_length()) {
                warning("lumen-desktop: cannot address widget %d of %u",
                    spec.index, arr.get_length());
                return null;
            }
            var node = arr.get_element((uint) spec.index);
            if (node.get_node_type() != Json.NodeType.OBJECT) return null;
            return node.get_object();
        }

        private static void write_positions(Json.Object entry, WidgetSpec spec) {
            if (spec.positions.size() == 0) {
                entry.remove_member("positions");
                return;
            }
            var po = new Json.Object();
            foreach (var key in spec.positions.get_keys()) {
                var p = spec.positions.lookup(key);
                var eo = new Json.Object();
                eo.set_int_member("x", p.x);
                eo.set_int_member("y", p.y);
                po.set_object_member(key, eo);
            }
            entry.set_object_member("positions", po);
        }

        // No usable file to patch. Settings are written as strings; getters coerce.
        private static Json.Node generate() {
            var arr = new Json.Array();
            foreach (var spec in widgets) {
                var o = new Json.Object();
                o.set_string_member("type", spec.type_name);
                o.set_string_member("shape", spec.shape_name);
                o.set_double_member("radius", spec.radius);
                o.set_int_member("width", spec.width);
                o.set_int_member("height", spec.height);
                o.set_int_member("x", spec.x);
                o.set_int_member("y", spec.y);
                o.set_double_member("border-width", spec.border_width);
                o.set_double_member("tab-height", spec.tab_height);
                o.set_double_member("tab-width", spec.tab_ratio);
                o.set_string_member("border-color", spec.border_color);

                var so = new Json.Object();
                foreach (var key in spec.settings.keys()) {
                    so.set_string_member(key, spec.settings.get_raw(key));
                }
                o.set_object_member("settings", so);

                write_positions(o, spec);
                arr.add_object_element(o);
            }

            var obj = new Json.Object();
            obj.set_array_member("widgets", arr);
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(obj);
            return node;
        }

        private static void write(Json.Node root) {
            var path = config_path();
            GLib.DirUtils.create_with_parents(GLib.Path.get_dirname(path), 0755);

            var gen = new Json.Generator();
            gen.set_root(root);
            gen.pretty = true;
            gen.indent = 2;
            try {
                gen.to_file(path);
            } catch (GLib.Error e) {
                warning("lumen-desktop: writing %s: %s", path, e.message);
            }
        }

        private static string? scalar_to_string(Json.Node node) {
            if (node.get_node_type() != Json.NodeType.VALUE) return null;
            var t = node.get_value_type();
            if (t == typeof(string)) return node.get_string();
            if (t == typeof(bool))   return node.get_boolean().to_string();
            if (t == typeof(int64))  return node.get_int().to_string();
            if (t == typeof(double)) {
                // Machine-facing: force '.' regardless of LC_NUMERIC.
                char[] buf = new char[double.DTOSTR_BUF_SIZE];
                return node.get_double().format(buf);
            }
            return null;
        }
    }
}
