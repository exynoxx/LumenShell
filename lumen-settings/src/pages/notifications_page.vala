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

            // Keys match the lumen-notifications theme schema (see Theme.load
            // in lumen-notifications) so edits here take effect directly.
            var placement = new BoxedList("Placement");
            placement.add_row(int_row("banner.margin.top",   "Margin top",   0, 200, 16, "px from the top edge of the screen"));
            placement.add_row(int_row("banner.margin.right", "Margin right", 0, 200, 16, "px from the right edge of the screen"));
            placement.add_row(int_row("banner.gap",          "Gap",          0, 40,  10, "px of vertical space between banners"));
            box.append(placement);

            var behavior = new BoxedList("Behavior");
            behavior.add_row(int_row("clear-all.threshold",
                                     "Clear-all threshold", 1, 50, 3,
                                     "show the Clear All button once the stack reaches this size"));
            box.append(behavior);

            var test = new BoxedList("Test");
            var test_row = new ActionRow("Send a test notification",
                                         "posts a sample banner through the notification daemon");
            var test_btn = new Gtk.Button.with_label("Send") {
                valign = Gtk.Align.CENTER,
            };
            test_btn.add_css_class("suggested-action");
            test_btn.clicked.connect(send_test_notification);
            test_row.set_suffix(test_btn);
            test.add_row(test_row);
            box.append(test);

            return box;
        }

        public override string? restart_target() { return "lumen-notifications"; }

        void send_test_notification() {
            try {
                var conn = Bus.get_sync(BusType.SESSION);

                var actions = new VariantBuilder(new VariantType("as"));
                actions.add("s", "ok");
                actions.add("s", "OK");
                actions.add("s", "later");
                actions.add("s", "Later");

                var hints = new VariantBuilder(new VariantType("a{sv}"));
                hints.add("{sv}", "urgency", new Variant.byte(1));  // normal

                conn.call_sync(
                    "org.freedesktop.Notifications",
                    "/org/freedesktop/Notifications",
                    "org.freedesktop.Notifications",
                    "Notify",
                    new Variant("(susss@as@a{sv}i)",
                                "Lumen Settings",
                                (uint32) 0,
                                "preferences-system-notifications-symbolic",
                                "Test notification",
                                "If you can read this, notifications are working.",
                                actions.end(),
                                hints.end(),
                                (int32) 5000),
                    new VariantType("(u)"),
                    DBusCallFlags.NONE,
                    -1,
                    null);
            } catch (Error e) {
                warning("lumen-settings: test notification failed: %s", e.message);
            }
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
