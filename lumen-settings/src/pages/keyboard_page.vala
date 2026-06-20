using Gtk;

namespace LumenSettings {

    public class KeyboardPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "keyboard"; } }
        public string title     { owned get { return "Keyboard"; } }
        public string icon_name { owned get { return "input-keyboard-symbolic"; } }

        InputSection input;
        XkbLayouts xkb;
        ComboRow variant_row;

        public Gtk.Widget build() {
            input = new InputSection();
            xkb = new XkbLayouts();

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            // --- Layout ---------------------------------------------------
            var layout_grp = new BoxedList("Layout");

            var cur_layout  = input.get_str("xkb_layout")  ?? "us";
            var cur_variant = input.get_str("xkb_variant") ?? "";

            var layout_row = new ComboRow("Layout", xkb.layout_names, xkb.layout_codes,
                cur_layout, "keyboard layout", true);
            layout_grp.add_row(layout_row);

            var vl = xkb.variants_for(cur_layout);
            variant_row = new ComboRow("Variant", vl.names, vl.codes,
                cur_variant, "layout variant", true);
            layout_grp.add_row(variant_row);

            layout_row.value_changed.connect((code) => {
                input.put("xkb_layout", code);
                // The previous variant belongs to the old layout — drop it and
                // refill the dropdown. repopulate() is guarded, so resetting the
                // selection does not write a stray variant.
                var v = xkb.variants_for(code);
                variant_row.repopulate(v.names, v.codes, "");
                input.put("xkb_variant", "");
            });
            variant_row.value_changed.connect((code) => {
                input.put("xkb_variant", code);
            });

            var opt_initial = input.get_str("xkb_options") ?? "";
            var opt_row = new EntryRow("Options", opt_initial,
                "advanced xkb options, e.g. ctrl:nocaps");
            opt_row.value_changed.connect((v) => input.put("xkb_options", v));
            layout_grp.add_row(opt_row);

            box.append(layout_grp);

            // --- Key repeat -----------------------------------------------
            var repeat = new BoxedList("Key repeat");
            repeat.add_row(input.int_row("kb_repeat_delay", "Repeat delay",
                50, 2000, 10, 400, "ms a key is held before it repeats"));
            repeat.add_row(input.int_row("kb_repeat_rate", "Repeat rate",
                1, 100, 1, 40, "key repeats per second"));
            box.append(repeat);

            // --- Lock keys ------------------------------------------------
            var locks = new BoxedList("Lock keys");
            locks.add_row(input.bool_row("kb_numlock_default_state",
                "Num Lock on at startup", false));
            locks.add_row(input.bool_row("kb_capslock_default_state",
                "Caps Lock on at startup", false));
            box.append(locks);

            return box;
        }
    }
}
