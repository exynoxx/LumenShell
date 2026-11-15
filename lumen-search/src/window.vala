// The Spotlight-style search surface: a pill that grows into a results list.
namespace LumenSearch {
    // Drawn rather than themed: some icon themes ship non-recolourable "-symbolic" glyphs.
    class Magnifier : Gtk.Widget {
        construct { width_request = 20; height_request = 20; valign = Gtk.Align.CENTER; }

        public override void snapshot(Gtk.Snapshot s) {
            var pb = new Gsk.PathBuilder();
            pb.add_circle({ 8.5f, 8.5f }, 6f);
            pb.move_to(13f, 13f);
            pb.line_to(18.5f, 18.5f);
            var stroke = new Gsk.Stroke(2f);
            stroke.set_line_cap(Gsk.LineCap.ROUND);
            s.append_stroke(pb.to_path(), stroke, get_color());
        }
    }

    public class SearchWindow : Gtk.Window {
        const int64 REFRESH_AGE_US = 60 * TimeSpan.SECOND;

        AppInfoMonitor app_monitor = AppInfoMonitor.get();
        Gtk.Text entry;
        Gtk.Revealer revealer;
        Gtk.ListBox list;
        Gtk.ScrolledWindow scroll;
        Gtk.Box card;

        Ranker ranker = new Ranker();
        Item[] apps = {};
        Item[] files = {};
        Hit[] contents = {};
        Results results = new Results();
        Query query = Query.parse("");

        int64 files_loaded_us = 0;
        bool files_loading;
        uint debounce_id;
        int generation;
        Cancellable? content_cancel;

        public SearchWindow(Gtk.Application app) {
            GLib.Object(application: app);
            GtkLayerShell.init_for_window(this);
            GtkLayerShell.set_namespace(this, "lumen-search");
            GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);
            GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.EXCLUSIVE);
            GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
            decorated = false;
            resizable = false;
            add_css_class("lumen-search-root");
            install_css();

            var glyph = new Magnifier();
            glyph.add_css_class("search-muted");
            entry = new Gtk.Text();
            entry.hexpand = true;
            entry.placeholder_text = "Search";
            var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            bar.add_css_class("search-bar");
            bar.height_request = 56;
            bar.append(glyph);
            bar.append(entry);

            list = new Gtk.ListBox();
            list.selection_mode = Gtk.SelectionMode.SINGLE;
            list.row_activated.connect((r) => open((ResultRow) r, false));
            scroll = new Gtk.ScrolledWindow();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 480;
            scroll.child = list;
            var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
            var results_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            results_box.append(sep);
            results_box.append(scroll);
            revealer = new Gtk.Revealer();
            revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            revealer.child = results_box;

            card = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            card.add_css_class("search-card");
            card.width_request = SearchConfig.width;
            card.append(bar);
            card.append(revealer);
            child = card;

            entry.changed.connect(on_changed);
            var keys = new Gtk.EventControllerKey();
            keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            keys.key_pressed.connect(on_key);
            ((Gtk.Widget) this).add_controller(keys);

            load_apps();
            app_monitor.changed.connect(load_apps);
            refresh_files();
        }

        public void toggle() {
            if (visible) { dismiss(); return; }
            place();
            present();
            entry.grab_focus();
            if (get_monotonic_time() - files_loaded_us > REFRESH_AGE_US) refresh_files();
        }

        void dismiss() {
            entry.text = "";
            set_visible(false);
        }

        // Monitor left unset so the compositor picks the focused output; margin uses the first monitor's height.
        void place() {
            var mon = (Gdk.Monitor?) get_display().get_monitors().get_item(0);
            if (mon == null) return;
            GtkLayerShell.set_margin(this, GtkLayerShell.Edge.TOP, mon.geometry.height / 5);
        }

        void load_apps() {
            apps = AppIndex.load();
            reindex();
        }

        void refresh_files() {
            if (files_loading) return;
            files_loading = true;
            var fi = new FileIndex();
            fi.load.begin(null, (o, r) => {
                files_loading = false;
                try {
                    files = fi.load.end(r);
                    files_loaded_us = get_monotonic_time();
                    reindex();
                } catch (GLib.Error e) {
                    warning("file index load failed");
                }
            });
        }

        void reindex() {
            Item[] all = apps;
            foreach (var f in files) all += f;
            ranker.set_items(all);
            if (entry.text != "") { results = ranker.search(query); rebuild(); }
        }

        void on_changed() {
            var text = entry.text;
            query = Query.parse(text);
            bool open_ = text != "";
            // Empty query matches everything; show the bare pill instead.
            results = open_ ? ranker.search(query) : new Results();
            contents = {};   // never show contents of an older query
            list.unselect_all();   // new text: select the new first row, not the old item
            scroll.vadjustment.value = 0;
            rebuild();

            generation++;
            if (content_cancel != null) content_cancel.cancel();
            content_cancel = null;
            if (debounce_id != 0) { Source.remove(debounce_id); debounce_id = 0; }
            if (!open_ || !SearchConfig.content) return;
            debounce_id = Timeout.add(150, () => {
                debounce_id = 0;
                run_content();
                return Source.REMOVE;
            });
        }

        void run_content() {
            int gen = generation;
            var c = new Cancellable();
            content_cancel = c;
            var cs = new ContentSearch();
            cs.run.begin(query, c, (o, r) => {
                Hit[] hits;
                try {
                    hits = cs.run.end(r);
                } catch (IOError.CANCELLED e) {
                    return;
                } catch (GLib.Error e) {
                    warning("content search failed");
                    return;
                }
                if (gen != generation) return;
                contents = hits;
                rebuild();
            });
        }

        void rebuild() {
            var sel = list.get_selected_row() as ResultRow;
            string? keep = sel != null ? sel.hit.item.uri : null;
            list.remove_all();
            bool type_active = query.mime_prefixes.length > 0 || query.apps_only;
            if (results.top != null) section("Top Hit", { results.top }, type_active);
            section("Applications", results.apps, type_active);
            section("Files", results.files, type_active);
            section("In Contents", contents, type_active);

            ResultRow? first = null, match = null;
            for (int i = 0; ; i++) {
                var r = list.get_row_at_index(i) as ResultRow;
                if (r == null) break;
                if (r.hit == null) continue;
                if (first == null) first = r;
                if (keep != null && match == null && r.hit.item.uri == keep) match = r;
            }
            list.select_row(match ?? first);
            // Expanded only while there is something to show.
            revealer.reveal_child = first != null;
            if (first != null) card.add_css_class("expanded"); else card.remove_css_class("expanded");
        }

        void section(string title, Hit[] hits, bool type_active) {
            if (hits.length == 0) return;
            list.append(new ResultRow.header(title));
            foreach (var h in hits) list.append(new ResultRow(h, type_active));
        }

        void move(int dir) {
            var cur = list.get_selected_row();
            int i = cur != null ? cur.get_index() : -1;
            for (i += dir; ; i += dir) {
                var r = list.get_row_at_index(i) as ResultRow;
                if (r == null) return;
                if (r.hit != null) {
                    list.select_row(r);
                    scroll_into_view(r);
                    return;
                }
            }
        }

        void scroll_into_view(Gtk.Widget r) {
            Graphene.Rect b;
            if (!r.compute_bounds(list, out b)) return;
            var adj = scroll.vadjustment;
            if (b.origin.y < adj.value) adj.value = b.origin.y;
            else if (b.origin.y + b.size.height > adj.value + adj.page_size)
                adj.value = b.origin.y + b.size.height - adj.page_size;
        }

        bool on_key(uint keyval, uint keycode, Gdk.ModifierType state) {
            switch (keyval) {
                case Gdk.Key.Escape:
                    if (entry.text != "") entry.text = ""; else dismiss();
                    return true;
                case Gdk.Key.Up:
                    move(-1);
                    return true;
                case Gdk.Key.Down:
                    move(1);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    var r = list.get_selected_row() as ResultRow;
                    if (r != null) open(r, (state & Gdk.ModifierType.CONTROL_MASK) != 0);
                    return true;
            }
            return false;
        }

        void open(ResultRow row, bool reveal) {
            var it = row.hit.item;
            var ctx = get_display().get_app_launch_context();
            try {
                if (it.app != null) it.app.launch(null, ctx);
                else if (reveal) show_in_folder(it.uri);
                else AppInfo.launch_default_for_uri_async.begin(it.uri, ctx, null);
            } catch (GLib.Error e) {
                warning("launch failed");
            }
            dismiss();
        }

        static void show_in_folder(string uri) {
            Bus.get.begin(BusType.SESSION, null, (o, r) => {
                try {
                    var bus = Bus.get.end(r);
                    bus.call.begin("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                        "org.freedesktop.FileManager1", "ShowItems",
                        new Variant("(^ass)", new string[] { uri }, ""),
                        null, DBusCallFlags.NONE, -1, null);
                } catch (GLib.Error e) {
                    warning("file manager unavailable");
                }
            });
        }

        void install_css() {
            var hl = Gdk.RGBA();
            hl.parse(SearchConfig.highlight);
            var sel = hl.copy();
            sel.alpha = 0.3f;
            var css = """
                window.lumen-search-root { background: transparent; }
                .search-card { background: %s; color: %s; border-radius: 28px;
                               margin: 24px; box-shadow: 0 8px 24px rgba(0,0,0,0.35); }
                .search-card.expanded { border-radius: 16px; }
                .search-bar { padding: 0 20px; }
                .search-bar text { font-size: 20px; color: %s; caret-color: %s; }
                .search-card separator { background: rgba(255,255,255,0.12); min-height: 1px; }
                .search-card scrolledwindow, .search-card list { background: transparent; }
                .search-card list { padding: 6px 8px 10px 8px; }
                .search-header { font-size: 11px; font-weight: bold; color: %s; padding: 8px 10px 2px 10px; }
                .search-row { padding: 6px 10px; border-radius: 8px; }
                .search-row:selected { background: %s; }
                .search-muted { color: %s; }
                .search-type-active { color: %s; font-weight: bold; }
            """.printf(rgba(SearchConfig.background), rgba(SearchConfig.text), rgba(SearchConfig.text),
                hl.to_string(), rgba(SearchConfig.muted_text), sel.to_string(),
                rgba(SearchConfig.muted_text), hl.to_string());
            var p = new Gtk.CssProvider();
            p.load_from_string(css);
            Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), p,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        // Round-trip through Gdk.RGBA so config strings can't inject CSS.
        static string rgba(string s) {
            var c = Gdk.RGBA();
            if (!c.parse(s)) c = { 1, 1, 1, 1 };
            return c.to_string();
        }
    }
}
