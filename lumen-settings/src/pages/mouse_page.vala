using Gtk;

namespace LumenSettings {

    public class MousePage : GLib.Object, SettingsPage {
        public string id        { owned get { return "mouse"; } }
        public string title     { owned get { return "Mouse"; } }
        public string icon_name { owned get { return "input-mouse-symbolic"; } }

        InputSection input;

        public Gtk.Widget build() {
            input = new InputSection();

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            string[] accel_labels = { "Default", "None", "Adaptive", "Flat" };
            string[] accel_values = { "default", "none", "adaptive", "flat" };

            var pointer = new BoxedList("Pointer");
            pointer.add_row(input.double_row("mouse_cursor_speed", "Pointer speed",
                -1.0, 1.0, 0.05, 0.0, 2, "−1 slowest, +1 fastest"));
            pointer.add_row(input.combo_row("mouse_accel_profile", "Acceleration profile",
                accel_labels, accel_values, "default", "pointer acceleration curve"));
            box.append(pointer);

            var scrolling = new BoxedList("Scrolling");
            scrolling.add_row(input.bool_row("mouse_natural_scroll", "Natural scrolling",
                false, "content follows finger/wheel direction"));
            scrolling.add_row(input.double_row("mouse_scroll_speed", "Scroll speed",
                0.0, 10.0, 0.1, 1.0, 1, "multiplier applied to wheel scrolling"));
            box.append(scrolling);

            var buttons = new BoxedList("Buttons");
            buttons.add_row(input.bool_row("middle_emulation", "Middle-click emulation",
                false, "press left + right together for middle click"));
            buttons.add_row(input.bool_row("left_handed_mode", "Left-handed mode",
                false, "swap the left and right buttons"));
            box.append(buttons);

            return box;
        }
    }
}
