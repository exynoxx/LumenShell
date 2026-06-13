using Gtk;

namespace LumenSettings {

    public class ActionRow : Gtk.ListBoxRow {
        protected Gtk.Box content;
        protected Gtk.Box text_col;
        protected Gtk.Label title_label;
        protected Gtk.Label subtitle_label;
        protected Gtk.Box   suffix_slot;

        string _title_text = "";
        string _subtitle_text = "";

        public string row_title {
            owned get { return _title_text; }
            set {
                _title_text = value;
                title_label.set_markup(format_title(value));
            }
        }
        public string row_subtitle {
            owned get { return _subtitle_text; }
            set {
                _subtitle_text = value ?? "";
                subtitle_label.set_markup(format_subtitle(_subtitle_text));
                subtitle_label.visible = (_subtitle_text != "");
            }
        }

        public ActionRow(string title, string subtitle = "") {
            _title_text = title;
            _subtitle_text = subtitle;

            content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
                hexpand = true,
            };
            text_col = new Gtk.Box(Gtk.Orientation.VERTICAL, 2) {
                hexpand = true, valign = Gtk.Align.CENTER,
            };
            title_label = new Gtk.Label(null) {
                xalign = 0,
                use_markup = true,
                wrap = false,
                ellipsize = Pango.EllipsizeMode.END,
            };
            title_label.set_markup(format_title(title));
            title_label.add_css_class("lumen-action-row-title");
            subtitle_label = new Gtk.Label(null) {
                xalign = 0,
                use_markup = true,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
            };
            subtitle_label.set_markup(format_subtitle(subtitle));
            subtitle_label.add_css_class("lumen-action-row-subtitle");
            subtitle_label.visible = (subtitle != "");
            text_col.append(title_label);
            text_col.append(subtitle_label);
            content.append(text_col);

            suffix_slot = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
                halign = Gtk.Align.END,
                valign = Gtk.Align.CENTER,
            };
            suffix_slot.add_css_class("lumen-row-suffix");
            content.append(suffix_slot);

            set_child(content);
            activatable = false;
        }

        public void set_suffix(Gtk.Widget w) {
            Gtk.Widget? child = suffix_slot.get_first_child();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling();
                suffix_slot.remove(child);
                child = next;
            }
            w.valign = Gtk.Align.CENTER;
            w.halign = Gtk.Align.END;
            w.hexpand = false;
            suffix_slot.append(w);
        }

        static string format_title(string s) {
            return "<b>" + Markup.escape_text(s) + "</b>";
        }
        static string format_subtitle(string s) {
            if (s == null || s == "") return "";
            return "<span size='small' style='italic' alpha='80%'>"
                + Markup.escape_text(s) + "</span>";
        }
    }
}
