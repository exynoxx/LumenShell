using Gtk;

namespace LumenSettings {

    /* Drag-to-reorder list of tray applets, each row a drag handle + label +
     * on/off switch. Built from an ordered (id, label, enabled) set — the Panel
     * page feeds it LumenTray.CATALOG ordered per the stored tray.order, with
     * each switch reflecting tray.disabled. Reordering uses GTK4's
     * DragSource/DropTarget on the rows (the idiomatic GTK4 approach); after any
     * reorder or toggle it emits `changed` with the full current order plus the
     * disabled subset, which the page persists to panel.json.
     *
     * Wrapped in a Gtk.ListBox so it drops cleanly inside an Adwaita boxed group
     * (BoxedList): the ListBox draws the row separators, this Box just carries
     * the list. */
    public class ReorderList : Gtk.Box {

        // One applet row. Holds its id and the live switch so the parent can
        // read the full order + enabled state back out on any change.
        class Row : Gtk.ListBoxRow {
            public string id;
            public Gtk.Switch sw;

            public Row(string id, string label, bool enabled) {
                this.id = id;

                var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
                    margin_top = 8, margin_bottom = 8,
                    margin_start = 12, margin_end = 12,
                };

                var handle = new Gtk.Image.from_icon_name("list-drag-handle-symbolic") {
                    valign = Gtk.Align.CENTER,
                };
                handle.add_css_class("dim-label");
                box.append(handle);

                var name = new Gtk.Label(label) {
                    halign = Gtk.Align.START,
                    hexpand = true,
                };
                box.append(name);

                sw = new Gtk.Switch() {
                    active = enabled,
                    valign = Gtk.Align.CENTER,
                };
                box.append(sw);

                child = box;
            }
        }

        Gtk.ListBox list;

        // Emitted after any reorder or toggle: `order` is every row top-to-bottom,
        // `disabled` is the subset whose switch is off.
        public signal void changed(string[] order, string[] disabled);

        public ReorderList(string[] ids, string[] labels, bool[] enabled) {
            GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            list = new Gtk.ListBox() {
                selection_mode = Gtk.SelectionMode.NONE,
            };
            list.add_css_class("boxed-list");
            append(list);

            for (int i = 0; i < ids.length; i++) {
                var row = new Row(ids[i], labels[i], enabled[i]);
                row.sw.notify["active"].connect(() => emit_changed());
                attach_dnd(row);
                list.append(row);
            }
        }

        // Wire one row as both a drag source (carries its own Row*) and a drop
        // target (re-inserts the dragged row before/after itself). Dropping on
        // the lower half of a row inserts after it, the upper half before.
        void attach_dnd(Row row) {
            var src = new Gtk.DragSource() {
                actions = Gdk.DragAction.MOVE,
            };
            src.prepare.connect((x, y) => {
                var v = Value(typeof(Row));
                v.set_object(row);
                return new Gdk.ContentProvider.for_value(v);
            });
            row.add_controller(src);

            var drop = new Gtk.DropTarget(typeof(Row), Gdk.DragAction.MOVE);
            drop.drop.connect((v, x, y) => {
                var dragged = v.get_object() as Row;
                if (dragged == null || dragged == row) return false;
                int target = row.get_index();
                // Inserting after when the pointer is in the lower half keeps the
                // drop position intuitive.
                bool after = y > row.get_height() / 2.0;
                list.remove(dragged);
                int idx = row.get_index();   // recompute: removal may have shifted it
                list.insert(dragged, after ? idx + 1 : idx);
                emit_changed();
                return true;
            });
            row.add_controller(drop);
        }

        void emit_changed() {
            string[] order = {};
            string[] disabled = {};
            for (int i = 0; ; i++) {
                var r = list.get_row_at_index(i) as Row;
                if (r == null) break;
                order += r.id;
                if (!r.sw.active) disabled += r.id;
            }
            changed(order, disabled);
        }
    }
}
