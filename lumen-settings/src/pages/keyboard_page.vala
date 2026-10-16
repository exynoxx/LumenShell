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

            var page = new Adw.PreferencesPage();

            // --- Layout ---------------------------------------------------
            var layout_grp = new Adw.PreferencesGroup() { title = "Layout" };

            var cur_layout  = input.get_str("xkb_layout")  ?? "us";
            var cur_variant = input.get_str("xkb_variant") ?? "";

            var layout_row = new ComboRow("Layout", xkb.layout_names, xkb.layout_codes,
                cur_layout, "keyboard layout");
            layout_grp.add(layout_row);

            var vl = xkb.variants_for(cur_layout);
            variant_row = new ComboRow("Variant", vl.names, vl.codes,
                cur_variant, "layout variant");
            layout_grp.add(variant_row);

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
            var opt_row = new Adw.EntryRow() {
                title = "Options",
                text = opt_initial,
                tooltip_text = "advanced xkb options, e.g. ctrl:nocaps",
            };
            opt_row.changed.connect(() => input.put("xkb_options", opt_row.text));
            layout_grp.add(opt_row);

            page.add(layout_grp);

            // --- Key repeat -----------------------------------------------
            var repeat = new Adw.PreferencesGroup() { title = "Key repeat" };
            repeat.add(input.int_row("kb_repeat_delay", "Repeat delay",
                50, 2000, 10, 400, "ms a key is held before it repeats"));
            repeat.add(input.int_row("kb_repeat_rate", "Repeat rate",
                1, 100, 1, 40, "key repeats per second"));
            page.add(repeat);

            // --- Lock keys ------------------------------------------------
            var locks = new Adw.PreferencesGroup() { title = "Lock keys" };
            locks.add(input.bool_row("kb_numlock_default_state",
                "Num Lock on at startup", false));
            locks.add(input.bool_row("kb_capslock_default_state",
                "Caps Lock on at startup", false));
            page.add(locks);

            return page;
        }
    }
}
