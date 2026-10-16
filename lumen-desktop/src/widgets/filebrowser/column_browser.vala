namespace LumenDesktop {

    public class ColumnBrowser : Gtk.Widget {

        private Gtk.ScrolledWindow scroller;
        private Gtk.Box strip;
        private GLib.List<FileColumn> columns = new GLib.List<FileColumn>();
        private int focused_column = 0;
        private bool show_hidden;

        public ColumnBrowser(GLib.File root, bool show_hidden) {
            this.show_hidden = show_hidden;

            set_layout_manager(new Gtk.BinLayout());
            focusable = true;

            strip = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            scroller = new Gtk.ScrolledWindow() {
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = Gtk.PolicyType.NEVER,
                child = strip,
                hexpand = true,
                vexpand = true,
            };
            scroller.set_parent(this);

            install_keys();
            push_column(root);
        }

        public override void dispose() {
            if (scroller != null) { scroller.unparent(); scroller = null; }
            base.dispose();
        }

        private void push_column(GLib.File dir) {
            if (columns.length() > 0) {
                var sep = new Gtk.Separator(Gtk.Orientation.VERTICAL);
                sep.add_css_class("fb-column-sep");
                strip.append(sep);
            }

            var col = new FileColumn(dir, show_hidden);
            int index = (int) columns.length();

            col.selection_changed.connect((entry) => on_selection(index, entry));
            col.clicked.connect(() => focused_column = index);
            col.activated.connect((entry) => {
                if (!entry.is_dir) FsModel.launch_default(entry.file);
            });

            strip.append(col);
            columns.append(col);
            scroll_to_end();
        }

        private void on_selection(int index, FsEntry? entry) {
            focused_column = index;
            truncate_after(index);
            if (entry != null && entry.is_dir) push_column(entry.file);
        }

        private void truncate_after(int index) {
            while ((int) columns.length() > index + 1) {
                var last = columns.nth_data(columns.length() - 1);
                var sep = last.get_prev_sibling();
                strip.remove(last);
                if (sep != null && sep is Gtk.Separator) strip.remove(sep);
                columns.remove(last);
            }
        }

        private void scroll_to_end() {
            var adj = scroller.get_hadjustment();
            if (adj == null) return;
            // The new column has no allocation yet; let the layout settle
            // first, otherwise upper == page_size and this is a no-op.
            GLib.Idle.add(() => {
                adj.value = adj.upper - adj.page_size;
                return GLib.Source.REMOVE;
            });
        }

        private void install_keys() {
            var key = new Gtk.EventControllerKey();
            key.key_pressed.connect(on_key_pressed);
            ((Gtk.Widget) this).add_controller(key);
        }

        private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
            var col = current_column();
            if (col == null) return false;

            switch (keyval) {
                case Gdk.Key.Up:
                    return col.move_selection(-1);
                case Gdk.Key.Down:
                    return col.move_selection(1);

                case Gdk.Key.Left:
                    if (focused_column > 0) {
                        focused_column--;
                        scroll_to_column(focused_column);
                    }
                    return true;

                case Gdk.Key.Right:
                    if (focused_column + 1 < (int) columns.length()) {
                        focused_column++;
                        columns.nth_data(focused_column).select_first_if_empty();
                        scroll_to_column(focused_column);
                    }
                    return true;

                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    col.activate_selected();
                    return true;
            }
            return false;
        }

        private FileColumn? current_column() {
            if (columns.length() == 0) return null;
            focused_column = int.max(0, int.min(focused_column, (int) columns.length() - 1));
            return columns.nth_data(focused_column);
        }

        private void scroll_to_column(int index) {
            var adj = scroller.get_hadjustment();
            if (adj == null) return;
            var col = columns.nth_data(index);
            if (col == null) return;
            GLib.Idle.add(() => {
                Gtk.Allocation alloc;
                col.get_allocation(out alloc);
                double x = alloc.x;
                double w = alloc.width;
                if (x < adj.value) adj.value = x;
                else if (x + w > adj.value + adj.page_size) adj.value = x + w - adj.page_size;
                return GLib.Source.REMOVE;
            });
        }
    }
}
