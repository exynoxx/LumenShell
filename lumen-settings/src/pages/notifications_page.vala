using Gtk;

namespace LumenSettings {

    public class NotificationsPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "notifications"; } }
        public string title     { owned get { return "Notifications"; } }
        public string icon_name { owned get { return "preferences-system-notifications-symbolic"; } }

        JsonStore store;

        public Gtk.Widget build() {
            store = new JsonStore(Paths.notifications_json());

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var placement = new BoxedList("Placement");
            placement.add_row(int_row("notifications.margin-top",   "Margin top",   0, 200, 24, "px from the top edge of the screen"));
            placement.add_row(int_row("notifications.margin-right", "Margin right", 0, 200, 24, "px from the right edge of the screen"));
            placement.add_row(int_row("notifications.gap",          "Gap",          0, 40,  8,  "px of vertical space between banners"));
            box.append(placement);

            var behavior = new BoxedList("Behavior");
            behavior.add_row(int_row("notifications.clear-threshold",
                                     "Clear-all threshold", 1, 50, 5,
                                     "show the Clear All button once the stack reaches this size"));
            box.append(behavior);

            return box;
        }

        SpinRow int_row(string key, string label, double min, double max,
                        int64 fallback, string subtitle = "") {
            var initial = (double) store.get_int(key, fallback);
            var row = new SpinRow(label, min, max, 1, initial, 0, subtitle);
            row.value_changed.connect((v) => {
                store.set_int(key, (int64) v);
                store.save();
            });
            return row;
        }
    }
}
