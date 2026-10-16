using Gtk;

namespace LumenSettings {

    public class MousePage : GLib.Object, SettingsPage {
        public string id        { owned get { return "mouse"; } }
        public string title     { owned get { return "Mouse"; } }
        public string icon_name { owned get { return "input-mouse-symbolic"; } }

        InputSection input;

        public Gtk.Widget build() {
            input = new InputSection();

            var page = new Adw.PreferencesPage();

            string[] accel_labels = { "Default", "None", "Adaptive", "Flat" };
            string[] accel_values = { "default", "none", "adaptive", "flat" };

            var pointer = new Adw.PreferencesGroup() { title = "Pointer" };
            pointer.add(input.double_row("mouse_cursor_speed", "Pointer speed",
                -1.0, 1.0, 0.05, 0.0, 2, "−1 slowest, +1 fastest"));
            pointer.add(input.combo_row("mouse_accel_profile", "Acceleration profile",
                accel_labels, accel_values, "default", "pointer acceleration curve"));
            page.add(pointer);

            var scrolling = new Adw.PreferencesGroup() { title = "Scrolling" };
            scrolling.add(input.bool_row("mouse_natural_scroll", "Natural scrolling",
                false, "content follows finger/wheel direction"));
            scrolling.add(input.double_row("mouse_scroll_speed", "Scroll speed",
                0.0, 10.0, 0.1, 1.0, 1, "multiplier applied to wheel scrolling"));
            page.add(scrolling);

            var buttons = new Adw.PreferencesGroup() { title = "Buttons" };
            buttons.add(input.bool_row("middle_emulation", "Middle-click emulation",
                false, "press left + right together for middle click"));
            buttons.add(input.bool_row("left_handed_mode", "Left-handed mode",
                false, "swap the left and right buttons"));
            page.add(buttons);

            return page;
        }
    }
}
