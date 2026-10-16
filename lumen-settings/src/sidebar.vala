namespace LumenSettings {

    public class Sidebar : Gtk.Box {
        public signal void page_selected(string id);

        Gtk.ListBox list;
        unowned PageRegistry registry;

        public Sidebar(PageRegistry r) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            registry = r;

            list = new Gtk.ListBox() {
                selection_mode = Gtk.SelectionMode.SINGLE,
                hexpand = true,
            };
            list.add_css_class("navigation-sidebar");
            list.set_header_func(update_header);

            append(new Gtk.ScrolledWindow() {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vexpand = true,
                child = list,
            });

            list.row_selected.connect((row) => {
                if (row == null) return;
                var id = row.get_data<string>("page-id");
                if (id != null) page_selected(id);
            });

            rebuild();
        }

        public void select_first() {
            var first = list.get_row_at_index(0);
            if (first != null) list.select_row(first);
        }

        void rebuild() {
            for (uint i = 0; i < registry.size; i++) {
                var page = registry.get_at(i);
                var row = make_row(page);
                row.set_data<string>("section", registry.section_at(i));
                list.append(row);
            }
            list.invalidate_headers();
        }

        void update_header(Gtk.ListBoxRow row, Gtk.ListBoxRow? before) {
            var section = row.get_data<string>("section") ?? "";
            var prev    = (before != null) ? (before.get_data<string>("section") ?? "") : "__none__";
            if (section == "" || section == prev || before == null) {
                row.set_header(null);
                return;
            }
            row.set_header(new Gtk.Separator(Gtk.Orientation.HORIZONTAL) {
                margin_top = 6, margin_bottom = 6,
            });
        }

        Gtk.ListBoxRow make_row(SettingsPage page) {
            var row = new Gtk.ListBoxRow();
            row.set_data<string>("page-id", page.id);

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);

            box.append(new Gtk.Image.from_icon_name(page.icon_name) {
                pixel_size = 16,
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.CENTER,
            });
            box.append(new Gtk.Label(page.title) {
                xalign = 0, hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                tooltip_text = page.title,
            });

            row.set_child(box);
            return row;
        }
    }
}
