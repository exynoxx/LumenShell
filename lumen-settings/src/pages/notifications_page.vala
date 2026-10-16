using LumenCommon;

namespace LumenSettings {

    public class NotificationsPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "notifications"; } }
        public string title     { owned get { return "Notifications"; } }
        public string icon_name { owned get { return "preferences-system-notifications-symbolic"; } }

        JsonRows rows;

        public Gtk.Widget build() {
            rows = new JsonRows(new JsonStore(Paths.notifications_json()));

            var page = new Adw.PreferencesPage();

            var placement = new Adw.PreferencesGroup() { title = "Placement" };
            placement.add(rows.int_row("banner.margin.top",   "Margin top",   0, 200, 1, 16, "px from the top edge of the screen"));
            placement.add(rows.int_row("banner.margin.right", "Margin right", 0, 200, 1, 16, "px from the right edge of the screen"));
            placement.add(rows.int_row("banner.gap",          "Gap",          0, 40,  1, 10, "px of vertical space between banners"));
            page.add(placement);

            var behavior = new Adw.PreferencesGroup() { title = "Behavior" };
            behavior.add(rows.int_row("clear-all.threshold",
                                          "Clear-all threshold", 1, 50, 1, 3,
                                          "show the Clear All button once the stack reaches this size"));
            page.add(behavior);

            var test = new Adw.PreferencesGroup() { title = "Test" };
            var test_row = new Adw.ActionRow() {
                title = "Send a test notification",
                subtitle = "posts a sample banner through the notification daemon",
            };
            var test_btn = new Gtk.Button.with_label("Send") {
                valign = Gtk.Align.CENTER,
            };
            test_btn.add_css_class("suggested-action");
            test_btn.clicked.connect(send_test_notification);
            test_row.add_suffix(test_btn);
            test.add(test_row);
            page.add(test);

            return page;
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
    }
}
