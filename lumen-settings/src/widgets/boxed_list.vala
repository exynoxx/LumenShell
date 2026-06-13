using Gtk;

namespace LumenSettings {

    public class BoxedList : Gtk.Box {
        public Gtk.ListBox list { get; private set; }

        public BoxedList(string? group_title = null) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            if (group_title != null && group_title != "") {
                append(build_section_header(group_title));
            }
            list = new Gtk.ListBox() {
                selection_mode = Gtk.SelectionMode.NONE,
                hexpand = true,
            };
            list.add_css_class("lumen-boxed-list");
            append(list);
        }

        static Gtk.Widget build_section_header(string title) {
            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10) {
                hexpand = true,
                valign = Gtk.Align.CENTER,
            };
            row.add_css_class("lumen-section-header");

            var left = new Gtk.Separator(Gtk.Orientation.HORIZONTAL) {
                hexpand = true, valign = Gtk.Align.CENTER,
            };
            left.add_css_class("lumen-section-rule");

            var label = new Gtk.Label(null) {
                use_markup = true,
                xalign = 0.5f,
            };
            label.set_markup(
                "<b>" + Markup.escape_text(title) + "</b>");
            label.add_css_class("lumen-section-title");

            var right = new Gtk.Separator(Gtk.Orientation.HORIZONTAL) {
                hexpand = true, valign = Gtk.Align.CENTER,
            };
            right.add_css_class("lumen-section-rule");

            row.append(left);
            row.append(label);
            row.append(right);
            return row;
        }

        public void add_row(Gtk.Widget row) {
            list.append(row);
        }
    }
}
