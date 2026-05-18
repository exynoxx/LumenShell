using GLib;
using Gee;

namespace LumenSettings.Wayfire {

    public enum OptionType {
        BOOL, INT, DOUBLE, STRING, COLOR, KEY, BUTTON, GESTURE,
        ACTIVATOR, ANIMATION, OUTPUT, DYNAMIC_LIST, UNKNOWN
    }

    public class EnumChoice : GLib.Object {
        public string value;
        public string name;
    }

    public class DynamicEntry : GLib.Object {
        public string prefix;
        public OptionType type;
        public string name;
        public string short_label;
    }

    public class OptionDef : GLib.Object {
        public string name;
        public OptionType type;
        public string short_label;
        public string long_label;
        public string default_value;
        public string min_value;
        public string max_value;
        public string precision;
        public string hint;
        public Gee.ArrayList<EnumChoice> choices = new Gee.ArrayList<EnumChoice>();
        public Gee.ArrayList<DynamicEntry> entries = new Gee.ArrayList<DynamicEntry>();
        public string type_hint;
        public string group_label;
    }

    public class PluginDef : GLib.Object {
        public string name;
        public string short_label;
        public string long_label;
        public string category;
        public Gee.ArrayList<OptionDef> options = new Gee.ArrayList<OptionDef>();
    }

    public class Metadata {
        static bool initialised = false;

        public static OptionType parse_type(string s) {
            switch (s) {
                case "bool":         return OptionType.BOOL;
                case "int":          return OptionType.INT;
                case "double":       return OptionType.DOUBLE;
                case "string":       return OptionType.STRING;
                case "color":        return OptionType.COLOR;
                case "key":          return OptionType.KEY;
                case "button":       return OptionType.BUTTON;
                case "gesture":      return OptionType.GESTURE;
                case "activator":    return OptionType.ACTIVATOR;
                case "animation":    return OptionType.ANIMATION;
                case "output":       return OptionType.OUTPUT;
                case "dynamic-list": return OptionType.DYNAMIC_LIST;
                default:             return OptionType.UNKNOWN;
            }
        }

        public static PluginDef? load_file(string path) {
            if (!initialised) {
                Xml.Parser.init();
                initialised = true;
            }

            Xml.Doc* doc = Xml.Parser.parse_file(path);
            if (doc == null) {
                stderr.printf("lumen-settings: wayfire metadata: failed to parse %s\n", path);
                return null;
            }

            Xml.Node* root = doc->get_root_element();
            if (root == null) {
                delete doc;
                stderr.printf("lumen-settings: wayfire metadata: empty doc %s\n", path);
                return null;
            }

            PluginDef? plugin = null;
            for (Xml.Node* c = root->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "plugin") {
                    plugin = parse_plugin(c);
                    break;
                }
            }

            delete doc;
            return plugin;
        }

        public static Gee.ArrayList<PluginDef> load_dir(string dir) {
            var result = new Gee.ArrayList<PluginDef>();
            try {
                Dir d = Dir.open(dir, 0);
                string? entry;
                while ((entry = d.read_name()) != null) {
                    if (!entry.has_suffix(".xml")) continue;
                    var path = Path.build_filename(dir, entry);
                    var plugin = load_file(path);
                    if (plugin != null) result.add(plugin);
                }
            } catch (Error e) {
                stderr.printf("lumen-settings: wayfire metadata: cannot list %s: %s\n",
                              dir, e.message);
            }

            result.sort((a, b) => {
                int c = strcmp(a.category, b.category);
                if (c != 0) return c;
                return strcmp(a.name, b.name);
            });
            return result;
        }

        static PluginDef parse_plugin(Xml.Node* node) {
            var p = new PluginDef();
            p.name = node->get_prop("name") ?? "";
            p.short_label = "";
            p.long_label = "";
            p.category = "";

            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "_short":
                        p.short_label = text_of(c);
                        break;
                    case "_long":
                        p.long_label = text_of(c);
                        break;
                    case "category":
                        p.category = text_of(c);
                        break;
                    case "option":
                        var o = parse_option(c, "");
                        if (o != null) p.options.add(o);
                        break;
                    case "group":
                        parse_group(c, p);
                        break;
                    default:
                        break;
                }
            }

            if (p.short_label == "") p.short_label = p.name;
            if (p.category == "") p.category = "Other";
            return p;
        }

        static void parse_group(Xml.Node* node, PluginDef plugin) {
            string label = "";
            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "_short") { label = text_of(c); break; }
            }
            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "option") {
                    var o = parse_option(c, label);
                    if (o != null) plugin.options.add(o);
                }
            }
        }

        static OptionDef? parse_option(Xml.Node* node, string group_label) {
            var o = new OptionDef();
            o.name = node->get_prop("name") ?? "";
            o.type = parse_type(node->get_prop("type") ?? "");
            o.type_hint = node->get_prop("type-hint") ?? "";
            o.group_label = group_label;
            o.short_label = "";
            o.long_label = "";
            o.default_value = "";
            o.min_value = "";
            o.max_value = "";
            o.precision = "";
            o.hint = "";

            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "_short":    o.short_label   = text_of(c); break;
                    case "_long":     o.long_label    = text_of(c); break;
                    case "default":   o.default_value = text_of(c); break;
                    case "min":       o.min_value     = text_of(c); break;
                    case "max":       o.max_value     = text_of(c); break;
                    case "precision": o.precision     = text_of(c); break;
                    case "hint":      o.hint          = text_of(c); break;
                    case "desc":      parse_desc(c, o); break;
                    case "entry":     parse_entry(c, o); break;
                    default: break;
                }
            }

            if (o.short_label == "") o.short_label = o.name;
            return o;
        }

        static void parse_desc(Xml.Node* node, OptionDef opt) {
            var ch = new EnumChoice();
            ch.value = "";
            ch.name = "";
            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "value") ch.value = text_of(c);
                else if (c->name == "_name") ch.name = text_of(c);
            }
            if (ch.name == "") ch.name = ch.value;
            opt.choices.add(ch);
        }

        static void parse_entry(Xml.Node* node, OptionDef opt) {
            var e = new DynamicEntry();
            e.prefix = node->get_prop("prefix") ?? "";
            e.type = parse_type(node->get_prop("type") ?? "");
            e.name = node->get_prop("name") ?? "";
            e.short_label = "";
            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "_short") { e.short_label = text_of(c); break; }
            }
            if (e.short_label == "") e.short_label = e.name;
            opt.entries.add(e);
        }

        static string text_of(Xml.Node* node) {
            string? s = node->get_content();
            if (s == null) return "";
            return s.strip();
        }
    }
}
