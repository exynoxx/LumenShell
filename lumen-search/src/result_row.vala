// One result row (or a non-selectable section header) in the search list.
namespace LumenSearch {
    public class ResultRow : Gtk.ListBoxRow {
        public Hit? hit;   // null for section headers

        public ResultRow.header(string title) {
            selectable = false;
            activatable = false;
            focusable = false;
            var l = new Gtk.Label(title.up());
            l.xalign = 0;
            l.add_css_class("search-header");
            child = l;
        }

        public ResultRow(Hit h, bool type_active) {
            hit = h;
            focusable = false;
            add_css_class("search-row");
            var it = h.item;

            GLib.Icon? gi = it.app != null ? it.app.get_icon()
                : ContentType.get_icon(it.mime != "" ? it.mime : "application/octet-stream");
            var icon = gi != null ? new Gtk.Image.from_gicon(gi) : new Gtk.Image.from_icon_name("application-x-executable");
            icon.pixel_size = 24;

            var name = new Gtk.Label(it.name);
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.attributes = highlight(it.name, h.name_pos);
            name.add_css_class("search-name");

            var text = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            text.hexpand = true;
            text.valign = Gtk.Align.CENTER;
            text.append(name);
            if (h.snippet_markup != null) {
                var snip = new Gtk.Label(null);
                snip.set_markup(h.snippet_markup);
                snip.xalign = 0;
                snip.ellipsize = Pango.EllipsizeMode.END;
                snip.add_css_class("search-muted");
                text.append(snip);
            }

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            box.append(icon);
            box.append(text);

            if (it.dir != "") {
                int[] dpos;
                var d = shorten(it.dir, h.dir_pos, out dpos);
                var dir = new Gtk.Label(d);
                dir.ellipsize = Pango.EllipsizeMode.START;
                dir.max_width_chars = 28;
                dir.attributes = highlight(d, dpos);
                dir.add_css_class("search-muted");
                box.append(dir);
            }

            string kind = it.kind == ItemKind.APP ? "Application"
                : (it.mime != "" ? ContentType.get_description(it.mime) : "");
            var type = new Gtk.Label(kind);
            type.add_css_class(type_active ? "search-type-active" : "search-muted");
            box.append(type);

            child = box;
        }

        // "~"-shortens a path and shifts its byte positions to match.
        static string shorten(string dir, int[] pos, out int[] out_pos) {
            var home = Environment.get_home_dir();
            int[] o = {};
            if (dir != home && !dir.has_prefix(home + "/")) {
                out_pos = pos;
                return dir;
            }
            int shift = home.length - 1;
            foreach (var p in pos) if (p >= home.length) o += p - shift;
            out_pos = o;
            return "~" + dir.substring(home.length);
        }

        // Bold + highlight colour over each matched char; positions are UTF-8 byte offsets.
        static Pango.AttrList highlight(string s, int[] pos) {
            var list = new Pango.AttrList();
            var c = Gdk.RGBA();
            c.parse(SearchConfig.highlight);
            foreach (var p in pos) {
                if (p < 0 || p >= s.length) continue;
                uint end = p + s.get_char(p).to_string().length;
                var w = Pango.attr_weight_new(Pango.Weight.BOLD);
                w.start_index = p; w.end_index = end;
                list.insert((owned) w);
                var f = Pango.attr_foreground_new((uint16) (c.red * 65535), (uint16) (c.green * 65535), (uint16) (c.blue * 65535));
                f.start_index = p; f.end_index = end;
                list.insert((owned) f);
            }
            return list;
        }
    }
}
