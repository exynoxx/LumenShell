namespace LumenSettings {

    public class TouchpadPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "touchpad"; } }
        public string title     { owned get { return "Touchpad"; } }
        public string icon_name { owned get { return "input-touchpad-symbolic"; } }

        InputSection input;

        public Gtk.Widget build() {
            input = new InputSection();

            var page = new Adw.PreferencesPage();

            string[] accel_labels = { "Default", "None", "Adaptive", "Flat" };
            string[] accel_values = { "default", "none", "adaptive", "flat" };

            var pointer = new Adw.PreferencesGroup() { title = "Pointer" };
            pointer.add(input.double_row("touchpad_cursor_speed", "Pointer speed",
                -1.0, 1.0, 0.05, 0.0, 2, "−1 slowest, +1 fastest"));
            pointer.add(input.combo_row("touchpad_accel_profile", "Acceleration profile",
                accel_labels, accel_values, "default", "pointer acceleration curve"));
            page.add(pointer);

            string[] click_labels = { "Default", "None", "Button areas", "Click finger" };
            string[] click_values = { "default", "none", "button-areas", "clickfinger" };

            var tapping = new Adw.PreferencesGroup() { title = "Tapping" };
            tapping.add(input.bool_row("tap_to_click", "Tap to click",
                true, "tap the pad to register a click"));
            tapping.add(input.bool_row("tap_and_drag", "Tap and drag",
                true, "tap then drag to move with the button held"));
            tapping.add(input.bool_row("drag_lock", "Drag lock",
                false, "keep dragging after lifting briefly"));
            tapping.add(input.combo_row("click_method", "Click method",
                click_labels, click_values, "default", "how physical clicks are detected"));
            page.add(tapping);

            string[] scroll_labels = { "Default", "None", "Two-finger", "Edge", "On button down" };
            string[] scroll_values = { "default", "none", "two-finger", "edge", "on-button-down" };

            var scrolling = new Adw.PreferencesGroup() { title = "Scrolling" };
            scrolling.add(input.bool_row("natural_scroll", "Natural scrolling",
                false, "content follows finger direction"));
            scrolling.add(input.double_row("touchpad_scroll_speed", "Scroll speed",
                0.0, 10.0, 0.1, 1.0, 1, "multiplier applied to two-finger scrolling"));
            scrolling.add(input.combo_row("scroll_method", "Scroll method",
                scroll_labels, scroll_values, "default", "gesture used to scroll"));
            page.add(scrolling);

            var behaviour = new Adw.PreferencesGroup() { title = "Behaviour" };
            behaviour.add(input.bool_row("disable_touchpad_while_typing",
                "Disable while typing", false, "ignore the pad shortly after key presses"));
            behaviour.add(input.bool_row("disable_touchpad_while_mouse",
                "Disable when mouse plugged in", false, "ignore the pad while an external mouse is present"));
            behaviour.add(input.double_row("gesture_sensitivity", "Gesture sensitivity",
                0.1, 5.0, 0.1, 1.0, 1, "multiplier for swipe/pinch gestures"));
            page.add(behaviour);

            return page;
        }
    }
}
