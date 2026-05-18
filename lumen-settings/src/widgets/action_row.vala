using Gtk;

namespace LumenSettings {

    /* GNOME-style "action row": title + optional subtitle on the left, an
     * arbitrary trailing widget on the right. Subclasses (SwitchRow,
     * ComboRow, ...) plug a control into set_suffix(). */
    public class ActionRow : Gtk.ListBoxRow {
        protected Gtk.Box content;
        protected Gtk.Box text_col;
        protected Gtk.Label title_label;
        protected Gtk.Label subtitle_label;
        Gtk.Widget? suffix_widget = null;

        public string row_title {
            owned get { return title_label.label; }
            set { title_label.label = value; }
        }
        public string row_subtitle {
            owned get { return subtitle_label.label; }
            set {
                subtitle_label.label = value;
                subtitle_label.visible = (value != null && value != "");
            }
        }

        public ActionRow(string title, string subtitle = "") {
            content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
                hexpand = true,
            };
            text_col = new Gtk.Box(Gtk.Orientation.VERTICAL, 2) {
                hexpand = true, valign = Gtk.Align.CENTER,
            };
            title_label = new Gtk.Label(title) { xalign = 0 };
            title_label.add_css_class("lumen-action-row-title");
            subtitle_label = new Gtk.Label(subtitle) { xalign = 0 };
            subtitle_label.add_css_class("lumen-action-row-subtitle");
            subtitle_label.visible = (subtitle != "");
            text_col.append(title_label);
            text_col.append(subtitle_label);
            content.append(text_col);
            set_child(content);
            activatable = false;
        }

        public void set_suffix(Gtk.Widget w) {
            if (suffix_widget != null) content.remove(suffix_widget);
            w.valign = Gtk.Align.CENTER;
            content.append(w);
            suffix_widget = w;
        }
    }
}
