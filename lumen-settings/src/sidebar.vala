using Gtk;

namespace LumenSettings {

    public class Sidebar : Gtk.Box {
        public signal void page_selected(string id);

        Gtk.ListBox list;
        unowned PageRegistry registry;

        public Sidebar(PageRegistry r) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            registry = r;
            add_css_class("lumen-settings-sidebar");
            set_size_request(220, -1);

            var scroller = new Gtk.ScrolledWindow() {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vexpand = true,
            };

            list = new Gtk.ListBox() {
                selection_mode = Gtk.SelectionMode.SINGLE,
                hexpand = true,
            };
            list.add_css_class("navigation-sidebar");
            list.set_header_func(update_header);

            scroller.set_child(list);
            append(scroller);

            list.row_selected.connect((row) => {
                if (row == null) return;
                var id = row.get_data<string>("page-id");
                if (id != null) page_selected(id);
            });

            registry.changed.connect(rebuild);
            rebuild();
        }

        public void select_first() {
            var first = list.get_row_at_index(0);
            if (first != null) list.select_row(first);
        }

        public void select_id(string id) {
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index(i);
                if (row == null) return;
                if (row.get_data<string>("page-id") == id) {
                    list.select_row(row);
                    return;
                }
            }
        }

        void rebuild() {
            Gtk.Widget? child = list.get_first_child();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling();
                list.remove(child);
                child = next;
            }
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
            if (section == "" || section == prev) {
                row.set_header(null);
                return;
            }

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
                margin_top    = (before == null) ? 4 : 14,
                margin_bottom = 2,
            };
            if (before != null) {
                var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL) {
                    margin_start = 12, margin_end = 12, margin_bottom = 6,
                };
                box.append(sep);
            }
            var label = new Gtk.Label(section) {
                xalign = 0,
                margin_start = 16, margin_end = 12,
            };
            label.add_css_class("lumen-sidebar-section");
            box.append(label);
            row.set_header(box);
        }

        Gtk.ListBoxRow make_row(SettingsPage page) {
            var row = new Gtk.ListBoxRow();
            row.set_data<string>("page-id", page.id);
            row.add_css_class("lumen-settings-sidebar-row");

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
                margin_start = 12, margin_end = 12,
                margin_top = 8, margin_bottom = 8,
            };
            var icon = new Gtk.Image.from_icon_name(page.icon_name) {
                pixel_size = 18,
            };
            var label = new Gtk.Label(page.title) {
                xalign = 0, hexpand = true,
            };
            box.append(icon);
            box.append(label);
            row.set_child(box);
            return row;
        }
    }
}
