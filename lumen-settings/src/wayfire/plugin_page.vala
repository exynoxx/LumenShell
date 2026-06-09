using Gtk;
using Gee;

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

        public Gtk.Widget build() {
            // The window already wraps every page body in a ScrolledWindow, so
            // this page must return a plain box — a second ScrolledWindow here
            // would produce nested (double) scrollbars.
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            if (plugin.long_label != "") {
                var lbl = new Gtk.Label(plugin.long_label) {
                    xalign = 0, wrap = true,
                };
                box.append(lbl);
            }

            var grouped = new Gee.HashMap<string, BoxedList>();
            var order = new Gee.ArrayList<string>();

            foreach (var opt in plugin.options) {
                var key = opt.group_label;
                BoxedList list;
                if (grouped.has_key(key)) {
                    list = grouped.get(key);
                } else {
                    list = new BoxedList(key != "" ? key : null);
                    grouped.set(key, list);
                    order.add(key);
                }
                var row = build_row(opt);
                if (row != null) list.add_row(row);
            }

            foreach (var k in order) {
                box.append(grouped.get(k));
            }

            return box;
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

        SwitchRow build_bool(OptionDef opt) {
            var raw = store.get_value(plugin.name, opt.name) ?? opt.default_value;
            bool initial = parse_bool(raw);
            var row = new SwitchRow(opt.short_label, opt.long_label, initial);
            row.toggled.connect((v) => {
                store.set_value(plugin.name, opt.name, v ? "true" : "false");
                store.save();
            });
            return row;
        }

        SpinRow build_int(OptionDef opt) {
            double min = parse_double(opt.min_value, -1000);
            double max = parse_double(opt.max_value, 1000);
            double initial = parse_double(store.get_value(plugin.name, opt.name)
                                          ?? opt.default_value, 0);
            var row = new SpinRow(opt.short_label, min, max, 1, initial, 0,
                                  opt.long_label);
            row.value_changed.connect((v) => {
                store.set_value(plugin.name, opt.name, "%d".printf((int) v));
                store.save();
            });
            return row;
        }

        SpinRow build_double(OptionDef opt) {
            double min = parse_double(opt.min_value, -1000);
            double max = parse_double(opt.max_value, 1000);
            double prec = parse_double(opt.precision, 0.01);
            double initial = parse_double(store.get_value(plugin.name, opt.name)
                                          ?? opt.default_value, 0);
            uint digits = digits_for(prec);
            var row = new SpinRow(opt.short_label, min, max, prec, initial,
                                  (double) digits, opt.long_label);
            row.value_changed.connect((v) => {
                store.set_value(plugin.name, opt.name, "%g".printf(v));
                store.save();
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
                    store.set_value(plugin.name, opt.name, v);
                    store.save();
                });
                return combo;
            }
            var entry = new EntryRow(opt.short_label, initial, opt.long_label);
            entry.value_changed.connect((v) => {
                store.set_value(plugin.name, opt.name, v);
                store.save();
            });
            return entry;
        }

        ColorRow build_color(OptionDef opt) {
            var initial = store.get_value(plugin.name, opt.name) ?? opt.default_value;
            var row = new ColorRow(opt.short_label, initial, opt.long_label);
            row.value_changed.connect((v) => {
                store.set_value(plugin.name, opt.name, v);
                store.save();
            });
            return row;
        }

        BindingRow build_binding(OptionDef opt) {
            var initial = store.get_value(plugin.name, opt.name) ?? opt.default_value;
            var row = new BindingRow(opt.short_label, initial, opt.long_label);
            row.value_changed.connect((v) => {
                store.set_value(plugin.name, opt.name, v);
                store.save();
            });
            return row;
        }

        EntryRow build_text(OptionDef opt) {
            var initial = store.get_value(plugin.name, opt.name) ?? opt.default_value;
            var row = new EntryRow(opt.short_label, initial, opt.long_label);
            row.value_changed.connect((v) => {
                store.set_value(plugin.name, opt.name, v);
                store.save();
            });
            return row;
        }

        Gtk.Widget build_dynamic_list(OptionDef opt) {
            var list = new BoxedList(opt.short_label);

            var tails = collect_dynamic_tails(opt);
            foreach (var tail in tails) {
                list.add_row(make_dynamic_row(opt, tail));
            }

            var add_button = new Gtk.Button.from_icon_name("list-add-symbolic") {
                halign = Gtk.Align.START,
                margin_top = 6,
            };
            add_button.add_css_class("flat");
            add_button.clicked.connect(() => {
                var next = next_tail(opt);
                foreach (var e in opt.entries) {
                    store.set_value(plugin.name, e.prefix + next, "");
                }
                store.save();
                list.add_row(make_dynamic_row(opt, next));
            });

            var outer = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            outer.append(list);
            outer.append(add_button);
            return outer;
        }

        Gtk.Widget make_dynamic_row(OptionDef opt, string tail) {
            var ar = new ActionRow(tail, "");
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            foreach (var e in opt.entries) {
                var key = e.prefix + tail;
                var current = store.get_value(plugin.name, key) ?? "";
                var sub = build_sub_entry(e, current, key);
                box.append(sub);
            }
            ar.set_suffix(box);
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
                        store.set_value(plugin.name, ini_key, v);
                        store.save();
                    });
                    return br;
                case OptionType.BOOL:
                    var sw = new SwitchRow(e.short_label, "", parse_bool(current));
                    sw.toggled.connect((v) => {
                        store.set_value(plugin.name, ini_key, v ? "true" : "false");
                        store.save();
                    });
                    return sw;
                default:
                    var er = new EntryRow(e.short_label, current, "");
                    er.value_changed.connect((v) => {
                        store.set_value(plugin.name, ini_key, v);
                        store.save();
                    });
                    return er;
            }
        }

        Gee.ArrayList<string> collect_dynamic_tails(OptionDef opt) {
            var seen = new Gee.HashSet<string>();
            var ordered = new Gee.ArrayList<string>();
            var keys = store.keys_in(plugin.name);
            foreach (var k in keys) {
                foreach (var e in opt.entries) {
                    if (e.prefix != "" && k.has_prefix(e.prefix)) {
                        var tail = k.substring(e.prefix.length);
                        if (!seen.contains(tail)) {
                            seen.add(tail);
                            ordered.add(tail);
                        }
                        break;
                    }
                }
            }
            return ordered;
        }

        string next_tail(OptionDef opt) {
            var existing = collect_dynamic_tails(opt);
            for (int i = 1; i < 1000; i++) {
                var cand = "%d".printf(i);
                if (!existing.contains(cand)) return cand;
            }
            return "new";
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
