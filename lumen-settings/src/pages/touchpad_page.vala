using Gtk;

namespace LumenSettings {

    public class TouchpadPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "touchpad"; } }
        public string title     { owned get { return "Touchpad"; } }
        public string icon_name { owned get { return "input-touchpad-symbolic"; } }

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
            pointer.add_row(input.double_row("touchpad_cursor_speed", "Pointer speed",
                -1.0, 1.0, 0.05, 0.0, 2, "−1 slowest, +1 fastest"));
            pointer.add_row(input.combo_row("touchpad_accel_profile", "Acceleration profile",
                accel_labels, accel_values, "default", "pointer acceleration curve"));
            box.append(pointer);

            string[] click_labels = { "Default", "None", "Button areas", "Click finger" };
            string[] click_values = { "default", "none", "button-areas", "clickfinger" };

            var tapping = new BoxedList("Tapping");
            tapping.add_row(input.bool_row("tap_to_click", "Tap to click",
                true, "tap the pad to register a click"));
            tapping.add_row(input.bool_row("tap_and_drag", "Tap and drag",
                true, "tap then drag to move with the button held"));
            tapping.add_row(input.bool_row("drag_lock", "Drag lock",
                false, "keep dragging after lifting briefly"));
            tapping.add_row(input.combo_row("click_method", "Click method",
                click_labels, click_values, "default", "how physical clicks are detected"));
            box.append(tapping);

            string[] scroll_labels = { "Default", "None", "Two-finger", "Edge", "On button down" };
            string[] scroll_values = { "default", "none", "two-finger", "edge", "on-button-down" };

            var scrolling = new BoxedList("Scrolling");
            scrolling.add_row(input.bool_row("natural_scroll", "Natural scrolling",
                false, "content follows finger direction"));
            scrolling.add_row(input.double_row("touchpad_scroll_speed", "Scroll speed",
                0.0, 10.0, 0.1, 1.0, 1, "multiplier applied to two-finger scrolling"));
            scrolling.add_row(input.combo_row("scroll_method", "Scroll method",
                scroll_labels, scroll_values, "default", "gesture used to scroll"));
            box.append(scrolling);

            var behaviour = new BoxedList("Behaviour");
            behaviour.add_row(input.bool_row("disable_touchpad_while_typing",
                "Disable while typing", false, "ignore the pad shortly after key presses"));
            behaviour.add_row(input.bool_row("disable_touchpad_while_mouse",
                "Disable when mouse plugged in", false, "ignore the pad while an external mouse is present"));
            behaviour.add_row(input.double_row("gesture_sensitivity", "Gesture sensitivity",
                0.1, 5.0, 0.1, 1.0, 1, "multiplier for swipe/pinch gestures"));
            box.append(behaviour);

            return box;
        }
    }
}
