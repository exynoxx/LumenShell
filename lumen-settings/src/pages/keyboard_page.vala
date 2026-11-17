namespace LumenSettings {

    public class KeyboardPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "keyboard"; } }
        public string title     { owned get { return "Keyboard"; } }
        public string icon_name { owned get { return "lumen-settings-keyboard"; } }

        InputSection input;
        XkbLayouts xkb;
        ComboRow variant_row;

        public Gtk.Widget build() {
            input = new InputSection();
            xkb = new XkbLayouts();

            var page = new Adw.PreferencesPage();

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
                // The old variant belongs to the previous layout; reset it.
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

            var repeat = new Adw.PreferencesGroup() { title = "Key repeat" };
            repeat.add(input.int_row("kb_repeat_delay", "Repeat delay",
                50, 2000, 10, 400, "ms a key is held before it repeats"));
            repeat.add(input.int_row("kb_repeat_rate", "Repeat rate",
                1, 100, 1, 40, "key repeats per second"));
            page.add(repeat);

            var locks = new Adw.PreferencesGroup() { title = "Lock keys" };
            locks.add(input.bool_row("kb_numlock_default_state",
                "Num Lock on at startup", false));
            locks.add(input.bool_row("kb_capslock_default_state",
                "Caps Lock on at startup", false));
            page.add(locks);

            page.add(build_shortcuts());

            return page;
        }

        // Wayfire [command] binding_<tail> / command_<tail> pairs.
        IniStore wf;
        Adw.PreferencesGroup shortcuts;

        Adw.PreferencesGroup build_shortcuts() {
            wf = new IniStore(LumenCommon.Paths.wayfire_ini());
            shortcuts = new Adw.PreferencesGroup() {
                title = "Shortcuts",
                description = "Run a command on a key combo (Wayfire command plugin)",
            };

            var add = new Gtk.Button.with_label("Add shortcut") { valign = Gtk.Align.CENTER };
            add.add_css_class("flat");
            add.clicked.connect(() => {
                string tail = "";
                wf.edit(() => {
                    tail = next_tail();
                    wf.set_value("command", "binding_" + tail, "");
                    wf.set_value("command", "command_" + tail, "");
                });
                var row = shortcut_row(tail);
                shortcuts.add(row);
                row.expanded = true;
            });
            shortcuts.set_header_suffix(add);

            var keys = wf.keys_in("command");
            foreach (var k in keys) {
                if (!k.has_prefix("binding_")) continue;
                var tail = k.substring("binding_".length);
                if (keys.contains("command_" + tail)) shortcuts.add(shortcut_row(tail));
            }
            return shortcuts;
        }

        Adw.ExpanderRow shortcut_row(string tail) {
            var bkey = "binding_" + tail, ckey = "command_" + tail;
            var cmd = wf.get_value("command", ckey) ?? "";
            var bind = wf.get_value("command", bkey) ?? "";

            var exp = new Adw.ExpanderRow() {
                title = cmd != "" ? cmd : "New shortcut",
                subtitle = bind != "" ? bind : "Unset",
                use_markup = false,
            };

            var cmd_row = new Adw.EntryRow() { title = "Command", text = cmd, use_markup = false };
            cmd_row.changed.connect(() => {
                put(ckey, cmd_row.text);
                exp.title = cmd_row.text != "" ? cmd_row.text : "New shortcut";
            });
            exp.add_row(cmd_row);

            var bind_row = new BindingRow("Binding", bind);
            bind_row.value_changed.connect((v) => {
                put(bkey, v);
                exp.subtitle = v != "" ? v : "Unset";
            });
            exp.add_row(bind_row);

            var del = new Gtk.Button.from_icon_name("user-trash-symbolic") {
                valign = Gtk.Align.CENTER, tooltip_text = "Remove shortcut",
            };
            del.add_css_class("flat");
            del.clicked.connect(() => {
                wf.edit(() => {
                    wf.remove_key("command", bkey);
                    wf.remove_key("command", ckey);
                });
                shortcuts.remove(exp);
            });
            exp.add_suffix(del);
            return exp;
        }

        void put(string key, string value) {
            wf.put("command", key, value);
        }

        // Unique across [command]: the repeatable/always/release lists share the tail space.
        string next_tail() {
            var keys = wf.keys_in("command");
            for (int i = 1; ; i++) {
                var cand = "%d".printf(i);
                bool taken = false;
                foreach (var k in keys) {
                    if (k.has_suffix("_" + cand)) { taken = true; break; }
                }
                if (!taken) return cand;
            }
        }
    }
}
