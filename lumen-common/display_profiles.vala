using GLib;

// Layouts keyed by the SET of connected output identities. Refresh is integer
// mHz end to end, so the file never carries a locale decimal separator.

public class DisplayOutputState : GLib.Object {
    public bool enabled;
    public int  width;
    public int  height;
    public int  refresh_mhz;
    public int  x;
    public int  y;
    public int  transform;
}

public class DisplayProfile : GLib.Object {
    // Sorted identity keys of every connected output in this profile (the set).
    public GenericArray<string> outputs = new GenericArray<string>();
    // identity -> desired state.
    public HashTable<string, DisplayOutputState> states =
        new HashTable<string, DisplayOutputState>(str_hash, str_equal);

    // Canonical key for the connected SET (order-independent).
    public string set_key() {
        var copy = new GenericArray<string>();
        for (int i = 0; i < outputs.length; i++) copy.add(outputs.get(i));
        copy.sort(strcmp);
        return string.joinv("|", copy.data);
    }
}

public class DisplayProfileStore {

    public static string path() {
        return LumenCommon.Paths.display_profiles_json();
    }

    // EDID → description → connector; port-independent unless it falls back
    // to the connector.
    public static string identity_for(string make, string model, string serial,
                                      string description, string connector) {
        string mk = make.strip(), md = model.strip(), sn = serial.strip();
        if (mk != "" || md != "" || sn != "")
            return "edid:%s:%s:%s".printf(mk, md, sn);
        if (description.strip() != "")
            return "desc:%s".printf(description.strip());
        return "conn:%s".printf(connector.strip());
    }

    // Identical serial-less monitors share one identity_for(). Suffix
    // "@<connector>" onto the colliding ones only, so a lone monitor keeps the
    // ID its saved profiles already use. ids[i] belongs to connectors[i].
    public static void disambiguate(GenericArray<string> ids, GenericArray<string> connectors) {
        var count = new HashTable<string, int>(str_hash, str_equal);
        for (int i = 0; i < ids.length; i++)
            count.set(ids.get(i), count.get(ids.get(i)) + 1);
        for (int i = 0; i < ids.length; i++)
            if (count.get(ids.get(i)) > 1)
                ids.set(i, "%s@%s".printf(ids.get(i), connectors.get(i).strip()));
    }

    public static string set_key_for(GenericArray<string> keys) {
        var p = new DisplayProfile();
        for (int i = 0; i < keys.length; i++) p.outputs.add(keys.get(i));
        return p.set_key();
    }

    public static GenericArray<DisplayProfile> load() {
        var list = new GenericArray<DisplayProfile>();
        var p = path();
        if (!FileUtils.test(p, FileTest.EXISTS)) return list;

        var parser = new Json.Parser();
        try {
            parser.load_from_file(p);
        } catch (Error e) {
            warning("display-profiles: parse %s: %s", p, e.message);
            return list;
        }
        var root = parser.get_root();
        if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return list;
        var obj = root.get_object();
        if (!obj.has_member("profiles")) return list;
        var arr = obj.get_array_member("profiles");
        if (arr == null) return list;

        arr.foreach_element((a, i, node) => {
            if (node.get_node_type() != Json.NodeType.OBJECT) return;
            var po = node.get_object();
            var prof = new DisplayProfile();
            if (po.has_member("outputs")) {
                var outs = po.get_array_member("outputs");
                if (outs != null) outs.foreach_element((aa, ii, n) => {
                    prof.outputs.add(n.get_string());
                });
            }
            if (po.has_member("states")) {
                var st = po.get_object_member("states");
                if (st != null) st.foreach_member((o2, key, n) => {
                    if (n.get_node_type() != Json.NodeType.OBJECT) return;
                    var so = n.get_object();
                    var s = new DisplayOutputState();
                    s.enabled     = so.has_member("enabled")   ? so.get_boolean_member("enabled") : true;
                    s.width       = so.has_member("w")         ? (int) so.get_int_member("w") : 0;
                    s.height      = so.has_member("h")         ? (int) so.get_int_member("h") : 0;
                    s.refresh_mhz = so.has_member("mhz")       ? (int) so.get_int_member("mhz") : 0;
                    s.x           = so.has_member("x")         ? (int) so.get_int_member("x") : 0;
                    s.y           = so.has_member("y")         ? (int) so.get_int_member("y") : 0;
                    s.transform   = so.has_member("transform") ? (int) so.get_int_member("transform") : 0;
                    prof.states.set(key, s);
                });
            }
            list.add(prof);
        });
        return list;
    }

    public static void save(GenericArray<DisplayProfile> profiles) {
        var builder = new Json.Builder();
        builder.begin_object();
        builder.set_member_name("profiles");
        builder.begin_array();
        for (int i = 0; i < profiles.length; i++) {
            var prof = profiles.get(i);
            builder.begin_object();

            builder.set_member_name("outputs");
            builder.begin_array();
            for (int k = 0; k < prof.outputs.length; k++)
                builder.add_string_value(prof.outputs.get(k));
            builder.end_array();

            builder.set_member_name("states");
            builder.begin_object();
            prof.states.foreach((key, s) => {
                builder.set_member_name(key);
                builder.begin_object();
                builder.set_member_name("enabled");   builder.add_boolean_value(s.enabled);
                builder.set_member_name("w");         builder.add_int_value(s.width);
                builder.set_member_name("h");         builder.add_int_value(s.height);
                builder.set_member_name("mhz");       builder.add_int_value(s.refresh_mhz);
                builder.set_member_name("x");         builder.add_int_value(s.x);
                builder.set_member_name("y");         builder.add_int_value(s.y);
                builder.set_member_name("transform"); builder.add_int_value(s.transform);
                builder.end_object();
            });
            builder.end_object();

            builder.end_object();
        }
        builder.end_array();
        builder.end_object();

        var gen = new Json.Generator();
        gen.set_root(builder.get_root());
        gen.pretty = true;

        var p = path();
        try {
            LumenCommon.Paths.ensure_dir();
            gen.to_file(p);
        } catch (Error e) {
            warning("display-profiles: write %s: %s", p, e.message);
        }
    }

    public static void save_or_update(DisplayProfile prof) {
        var all = load();
        var key = prof.set_key();
        var kept = new GenericArray<DisplayProfile>();
        for (int i = 0; i < all.length; i++) {
            if (all.get(i).set_key() != key) kept.add(all.get(i));
        }
        kept.add(prof);
        save(kept);
    }

    public static DisplayProfile? match(GenericArray<string> current_keys) {
        var want = set_key_for(current_keys);
        var all = load();
        for (int i = 0; i < all.length; i++) {
            if (all.get(i).set_key() == want) return all.get(i);
        }
        return null;
    }
}
