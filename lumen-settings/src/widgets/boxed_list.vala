using Gtk;

namespace LumenSettings {

    /* Vertical container with a group title above a boxed listbox. */
    public class BoxedList : Gtk.Box {
        public Gtk.ListBox list { get; private set; }

        public BoxedList(string? group_title = null) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            if (group_title != null && group_title != "") {
                var t = new Gtk.Label(group_title) { xalign = 0 };
                t.add_css_class("lumen-boxed-list-group-title");
                append(t);
            }
            list = new Gtk.ListBox() {
                selection_mode = Gtk.SelectionMode.NONE,
                hexpand = true,
            };
            list.add_css_class("lumen-boxed-list");
            append(list);
        }

        public void add_row(Gtk.Widget row) {
            list.append(row);
        }
    }
}
