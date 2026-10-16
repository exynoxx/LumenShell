namespace LumenDesktop {

    public class FileColumn : Gtk.Widget {

        public const int WIDTH = 220;

        public GLib.File dir { get; construct; }
        public bool show_hidden { get; construct; }

        public signal void selection_changed(FsEntry? entry);
        public signal void activated(FsEntry entry);
        // Covers re-clicking the selected row, which changes no selection but
        // must still move keyboard focus to this column.
        public signal void clicked();

        private Gtk.ScrolledWindow scroller;
        private Gtk.ListView list;
        private GLib.ListStore store = new GLib.ListStore(typeof(FsEntry));
        private Gtk.SingleSelection selection;

        public FileColumn(GLib.File dir, bool show_hidden) {
            Object(dir: dir, show_hidden: show_hidden);

            set_layout_manager(new Gtk.BinLayout());

            selection = new Gtk.SingleSelection(store) {
                autoselect = false,
                can_unselect = true,
            };
            selection.notify["selected"].connect(on_selection_changed);

            var factory = new Gtk.SignalListItemFactory();
            factory.setup.connect((obj) => {
                var item = (Gtk.ListItem) obj;
                var row = new FileRow();
                item.child = row;
                // Load-bearing (with list.focusable): ColumnBrowser must get the arrow keys.
                item.focusable = false;
                item.bind_property("selected", row, "selected",
                                   GLib.BindingFlags.SYNC_CREATE);
            });
            factory.bind.connect((obj) => {
                var item = (Gtk.ListItem) obj;
                ((FileRow) item.child).entry = (FsEntry) item.item;
            });
            factory.unbind.connect((obj) => {
                ((FileRow) ((Gtk.ListItem) obj).child).entry = null;
            });

            list = new Gtk.ListView(selection, factory) {
                focusable = false,
                margin_top = 6, margin_bottom = 6,
            };
            list.add_css_class("fb-list");
            // single_click_activate off: click selects (reveals), double-click launches.
            list.activate.connect(on_activate);

            scroller = new Gtk.ScrolledWindow() {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                child = list,
                hexpand = false,
                vexpand = true,
            };
            scroller.set_size_request(WIDTH, -1);
            scroller.set_parent(this);

            // CAPTURE and never claims: the list still does its own selecting.
            var click = new Gtk.GestureClick();
            click.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
            click.pressed.connect(() => clicked());
            add_controller(click);

            load.begin();
        }

        public override void dispose() {
            if (scroller != null) { scroller.unparent(); scroller = null; }
            base.dispose();
        }

        public override void measure(Gtk.Orientation orientation, int for_size,
                                     out int minimum, out int natural,
                                     out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = -1;
            natural_baseline = -1;
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                minimum = WIDTH;
                natural = WIDTH;
            } else {
                minimum = 0;
                natural = 0;
            }
        }

        private async void load() {
            GLib.List<FsEntry> entries;
            try {
                entries = yield FsModel.list_async(dir, show_hidden);
            } catch (GLib.Error e) {
                show_placeholder(e.message);
                return;
            }

            if (entries.length() == 0) {
                show_placeholder("Empty folder");
                return;
            }

            foreach (var entry in entries) store.append(entry);
        }

        private void show_placeholder(string text) {
            var placeholder = new Gtk.Label(text) {
                wrap = true,
                justify = Gtk.Justification.CENTER,
                margin_start = 10, margin_end = 10, margin_top = 10,
                valign = Gtk.Align.START,
                xalign = 0.5f,
            };
            placeholder.add_css_class("fb-empty");
            scroller.set_child(placeholder);
        }

        private void on_selection_changed() {
            var entry = selection.selected_item as FsEntry;
            if (entry != null) {
                list.scroll_to(selection.selected, Gtk.ListScrollFlags.NONE, null);
            }
            selection_changed(entry);
        }

        private void on_activate(uint position) {
            var entry = store.get_item(position) as FsEntry;
            if (entry != null) activated(entry);
        }

        public bool move_selection(int delta) {
            uint n = store.get_n_items();
            if (n == 0) return false;
            uint cur = selection.selected;
            int idx = (cur == Gtk.INVALID_LIST_POSITION) ? -1 : (int) cur;
            int next = idx < 0 ? (delta > 0 ? 0 : (int) n - 1) : idx + delta;
            next = int.max(0, int.min(next, (int) n - 1));
            if (next == idx) return true;
            selection.selected = next;
            return true;
        }

        public void select_first_if_empty() {
            if (selection.selected == Gtk.INVALID_LIST_POSITION) move_selection(1);
        }

        public void activate_selected() {
            var entry = selection.selected_item as FsEntry;
            if (entry != null) activated(entry);
        }
    }
}
