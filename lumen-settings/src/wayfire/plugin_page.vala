namespace LumenSettings.Wayfire {

    public class PluginPage : GLib.Object, SettingsPage {
        PluginDef plugin;
        IniStore store;
        string _id;

        public string id        { owned get { return _id; } }
        public string title     { owned get { return plugin.short_label; } }
        public string icon_name { owned get { return "preferences-other-symbolic"; } }

        public PluginPage(PluginDef plugin, IniStore store) {
            this.plugin = plugin;
            this.store = store;
            this._id = "wayfire-" + plugin.name;
        }

        // Other pages write wayfire.ini too; never save a stale snapshot.
        void put(string key, string value) {
            store.reload();
            store.set_value(plugin.name, key, value);
            store.save();
        }

        public Gtk.Widget build() {
            var page = new Adw.PreferencesPage() {
                description = Markup.escape_text(plugin.long_label),
            };

            var grouped = new Gee.HashMap<string, Adw.PreferencesGroup>();
            var order = new Gee.ArrayList<string>();

            foreach (var opt in plugin.options) {
                var key = opt.group_label;
                Adw.PreferencesGroup list;
                if (grouped.has_key(key)) {
                    list = grouped.get(key);
                } else {
                    list = new Adw.PreferencesGroup() { title = Markup.escape_text(key) };
                    grouped.set(key, list);
                    order.add(key);
                }
                var row = build_row(opt);
                if (row != null) list.add(row);
            }

            foreach (var k in order) {
                page.add(grouped.get(k));
            }

            return page;
        }

        Gtk.Widget? build_row(OptionDef opt) {
            switch (opt.type) {
                case OptionType.BOOL:         return build_bool(opt);
                case OptionType.INT:          return build_int(opt);
                case OptionType.DOUBLE:       return build_double(opt);
                case OptionType.STRING:       return build_string(opt);
                case OptionType.COLOR:        return build_color(opt);
                case OptionType.KEY:
                case OptionType.BUTTON:
                case OptionType.GESTURE:
                case OptionType.ACTIVATOR:    return build_binding(opt);
                case OptionType.ANIMATION:    return build_text(opt);
                case OptionType.OUTPUT:       return build_text(opt);
                case OptionType.DYNAMIC_LIST: return build_dynamic_list(opt);
                default:                      return build_text(opt);
            }
        }

        Adw.SwitchRow build_bool(OptionDef opt) {
            var raw = store.get_value(plugin.name, opt.name) ?? opt.default_value;
            var row = new Adw.SwitchRow() {
                title = opt.short_label, subtitle = opt.long_label,
                active = parse_bool(raw), use_markup = false,
            };
            row.notify["active"].connect(() => {
                put(opt.name, row.active ? "true" : "false");
            });
            return row;
        }

        Adw.SpinRow build_int(OptionDef opt) {
            double min = parse_double(opt.min_value, -1000);
            double max = parse_double(opt.max_value, 1000);
            double initial = parse_double(store.get_value(plugin.name, opt.name)
                                          ?? opt.default_value, 0);
            var row = SettingsRows.spin_row(opt.short_label, min, max, 1, initial, 0,
                                            opt.long_label);
            row.use_markup = false;
            row.notify["value"].connect(() => {
                put(opt.name, "%d".printf((int) row.value));
            });
            return row;
        }

        Adw.SpinRow build_double(OptionDef opt) {
            double min = parse_double(opt.min_value, -1000);
            double max = parse_double(opt.max_value, 1000);
            double prec = parse_double(opt.precision, 0.01);
            double initial = parse_double(store.get_value(plugin.name, opt.name)
                                          ?? opt.default_value, 0);
            var row = SettingsRows.spin_row(opt.short_label, min, max, prec, initial,
                                            digits_for(prec), opt.long_label);
            row.use_markup = false;
            row.notify["value"].connect(() => {
                put(opt.name, "%g".printf(row.value));
            });
            return row;
        }

        Gtk.Widget build_string(OptionDef opt) {
            var initial = store.get_value(plugin.name, opt.name) ?? opt.default_value;
            if (opt.choices.size > 0) {
                string[] labels = new string[opt.choices.size];
                string[] values = new string[opt.choices.size];
                for (int i = 0; i < opt.choices.size; i++) {
                    labels[i] = opt.choices.get(i).name;
                    values[i] = opt.choices.get(i).value;
                }
                var combo = new ComboRow(opt.short_label, labels, values, initial,
                                         opt.long_label);
                combo.value_changed.connect((v) => {
                    put(opt.name, v);
                });
                return combo;
            }
            return build_text(opt);
        }

        ColorRow build_color(OptionDef opt) {
            var initial = store.get_value(plugin.name, opt.name) ?? opt.default_value;
            var row = new ColorRow(opt.short_label, initial, opt.long_label);
            row.value_changed.connect((v) => {
                put(opt.name, v);
            });
            return row;
        }

        BindingRow build_binding(OptionDef opt) {
            var initial = store.get_value(plugin.name, opt.name) ?? opt.default_value;
            var row = new BindingRow(opt.short_label, initial, opt.long_label);
            row.value_changed.connect((v) => {
                put(opt.name, v);
            });
            return row;
        }

        Adw.EntryRow build_text(OptionDef opt) {
            var initial = store.get_value(plugin.name, opt.name) ?? opt.default_value;
            var row = new Adw.EntryRow() {
                title = opt.short_label, text = initial,
                tooltip_text = opt.long_label, use_markup = false,
            };
            row.changed.connect(() => {
                put(opt.name, row.text);
            });
            return row;
        }

        Gtk.Widget build_dynamic_list(OptionDef opt) {
            var list = new Adw.PreferencesGroup() { title = Markup.escape_text(opt.short_label) };

            var tails = collect_dynamic_tails(opt);
            foreach (var tail in tails) {
                list.add(make_dynamic_row(opt, tail, list));
            }

            var add_button = new Gtk.Button.from_icon_name("list-add-symbolic") {
                halign = Gtk.Align.START,
                margin_top = 6,
            };
            add_button.add_css_class("flat");
            add_button.clicked.connect(() => {
                store.reload();
                var next = next_tail(opt);
                foreach (var e in opt.entries) {
                    store.set_value(plugin.name, e.prefix + next, "");
                }
                store.save();
                list.add(make_dynamic_row(opt, next, list));
            });

            var outer = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            outer.append(list);
            outer.append(add_button);
            return outer;
        }

        Gtk.Widget make_dynamic_row(OptionDef opt, string tail, Adw.PreferencesGroup list) {
            var ar = new Adw.ActionRow() { title = tail, use_markup = false };
            var remove_button = new Gtk.Button.from_icon_name("user-trash-symbolic") {
                valign = Gtk.Align.CENTER,
                tooltip_text = "Remove",
            };
            remove_button.add_css_class("flat");
            remove_button.clicked.connect(() => {
                store.reload();
                foreach (var e in opt.entries) {
                    store.remove_key(plugin.name, e.prefix + tail);
                }
                store.save();
                list.remove(ar);
            });
            ar.add_prefix(remove_button);
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) { valign = Gtk.Align.CENTER };
            foreach (var e in opt.entries) {
                var key = e.prefix + tail;
                var current = store.get_value(plugin.name, key) ?? "";
                var sub = build_sub_entry(e, current, key);
                box.append(sub);
            }
            ar.add_suffix(box);
            return ar;
        }

        Gtk.Widget build_sub_entry(DynamicEntry e, string current, string ini_key) {
            switch (e.type) {
                case OptionType.KEY:
                case OptionType.BUTTON:
                case OptionType.GESTURE:
                case OptionType.ACTIVATOR:
                    var br = new BindingRow(e.short_label, current, "");
                    br.value_changed.connect((v) => {
                        put(ini_key, v);
                    });
                    return br;
                case OptionType.BOOL:
                    var sw = new Adw.SwitchRow() {
                        title = e.short_label, active = parse_bool(current), use_markup = false,
                    };
                    sw.notify["active"].connect(() => {
                        put(ini_key, sw.active ? "true" : "false");
                    });
                    return sw;
                default:
                    var er = new Adw.EntryRow() {
                        title = e.short_label, text = current, use_markup = false,
                    };
                    er.changed.connect(() => {
                        put(ini_key, er.text);
                    });
                    return er;
            }
        }

        // A tail belongs to this list only if every entry's key exists: lists
        // share prefixes (all [command] lists use command_), so matching any
        // one prefix would show every command in every list.
        Gee.ArrayList<string> collect_dynamic_tails(OptionDef opt) {
            var ordered = new Gee.ArrayList<string>();
            if (opt.entries.size == 0) return ordered;
            var keys = store.keys_in(plugin.name);
            var first = opt.entries.get(0).prefix;
            foreach (var k in keys) {
                if (first == "" || !k.has_prefix(first)) continue;
                var tail = k.substring(first.length);
                bool all = true;
                foreach (var e in opt.entries) {
                    if (!keys.contains(e.prefix + tail)) { all = false; break; }
                }
                if (all && !ordered.contains(tail)) ordered.add(tail);
            }
            return ordered;
        }

        // Unique across the whole section, since sibling lists share prefixes.
        string next_tail(OptionDef opt) {
            var keys = store.keys_in(plugin.name);
            for (int i = 1; ; i++) {
                var cand = "%d".printf(i);
                bool taken = false;
                foreach (var k in keys) {
                    if (k.has_suffix("_" + cand)) { taken = true; break; }
                }
                if (!taken) return cand;
            }
        }

        static bool parse_bool(string s) {
            var t = s.down().strip();
            return t == "true" || t == "1" || t == "yes" || t == "on";
        }

        static double parse_double(string s, double fallback) {
            if (s == null || s == "") return fallback;
            double d;
            return double.try_parse(s, out d) ? d : fallback;
        }

        static uint digits_for(double precision) {
            if (precision >= 1) return 0;
            if (precision >= 0.1) return 1;
            if (precision >= 0.01) return 2;
            if (precision >= 0.001) return 3;
            return 4;
        }
    }
}
