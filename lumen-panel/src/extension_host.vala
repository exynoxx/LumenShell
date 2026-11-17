// Baked in by meson (lumen_ext_c_args); $LUMEN_EXT_VAPIDIR / $LUMEN_EXT_PCDIR override.
[CCode (cname = "LUMEN_EXT_VAPIDIR")]
extern const string LUMEN_EXT_VAPIDIR;
[CCode (cname = "LUMEN_EXT_PCDIR")]
extern const string LUMEN_EXT_PCDIR;

// Compiles, loads and enables user extensions into the panel's registry, after
// the built-ins. Crash guard: the id being enabled is written to `enabling` and
// removed afterwards; finding it at startup means that enable() took the panel
// down, so the id goes to `crashed` and is skipped for the rest of the session
// ($XDG_RUNTIME_DIR, so a reboot clears it). There is no restarter to count loops.
public class ExtensionHost : GLib.Object {

    Lumen.Registry registry;
    Lumen.ExtensionConfig config;
    Gtk.Application app;
    Json.Object status = new Json.Object();
    string run_dir;
    string[] crashed = {};

    public ExtensionHost (Lumen.Registry registry, Lumen.ExtensionConfig config, Gtk.Application app) {
        this.registry = registry;
        this.config = config;
        this.app = app;
        run_dir = Path.get_dirname(LumenCommon.Paths.extensions_status_json());
        DirUtils.create_with_parents(run_dir, 0700);

        var enabling = run_dir + "/enabling";
        var crashed_path = run_dir + "/crashed";
        string list = read_or_empty(crashed_path);
        string id = read_or_empty(enabling).strip();
        if (id != "") {
            warning("lumen-panel: extension %s: crashed during enable last run; skipping it this session", id);
            list += id + "\n";
            try {
                FileUtils.set_contents(crashed_path, list);
            } catch (FileError e) {
                warning("lumen-panel: cannot record crashed extension: %s", e.message);
            }
        }
        FileUtils.remove(enabling);
        foreach (var l in list.split("\n")) if (l.strip() != "") crashed += l.strip();
    }

    static string read_or_empty (string path) {
        string text;
        try {
            FileUtils.get_contents(path, out text);
        } catch (FileError e) {
            return "";   // out params are nulled on failure
        }
        return text;
    }

    // True when a tray slot changed, i.e. the trays need rebuilding.
    public async bool load_all () {
        if (Environment.get_variable("LUMEN_SAFE_MODE") != null) {
            message("lumen-panel: LUMEN_SAFE_MODE set; not loading extensions");
            write_status();
            return false;
        }

        var compiler = new Lumen.Compiler(
            LumenCommon.Paths.extension_cache_dir(),
            Environment.get_variable("LUMEN_EXT_VAPIDIR") ?? LUMEN_EXT_VAPIDIR,
            Environment.get_variable("LUMEN_EXT_PCDIR") ?? LUMEN_EXT_PCDIR);

        // Compile everything in parallel, then enable in discovery order.
        var manifests = Lumen.Loader.discover({ LumenCommon.Paths.extensions_dir() });
        var built = new GLib.HashTable<string, string>(str_hash, str_equal);
        int pending = 1;   // held until every build is started
        foreach (var m in manifests) {
            if (!config.is_enabled(m.id)) { set_status(m.id, "disabled", ""); continue; }
            if (m.id in crashed) { fail(m.id, "crashed during enable"); continue; }
            pending++;
            compiler.build.begin(m, null, (obj, res) => {
                try {
                    built.insert(m.id, compiler.build.end(res));
                } catch (GLib.Error e) {
                    fail(m.id, e.message);
                }
                if (--pending == 0) load_all.callback();
            });
        }
        if (--pending > 0) yield;

        bool tray_changed = false;
        var handler = registry.changed.connect((slot) => {
            if (slot == Lumen.SLOT_TRAY_APPLET || slot == Lumen.SLOT_TRAY_PRESENTER) tray_changed = true;
        });
        foreach (var m in manifests) {
            var so = built.lookup(m.id);
            if (so != null) enable(m, so);
        }
        registry.disconnect(handler);

        write_status();
        return tray_changed;
    }

    void enable (Lumen.Manifest m, string so) {
        Lumen.Extension ext;
        try {
            ext = Lumen.Loader.load(so);
        } catch (Lumen.LoadError e) {
            fail(m.id, e.message);
            return;
        }
        var enabling = run_dir + "/enabling";
        try {
            FileUtils.set_contents(enabling, m.id);
        } catch (FileError e) {
            warning("lumen-panel: crash guard unavailable: %s", e.message);
        }
        var ctx = new Lumen.Context(m, registry, config, app);
        try {
            ext.enable(ctx);
            set_status(m.id, "loaded", "");
            message("lumen-panel: extension %s: loaded", m.id);
        } catch (GLib.Error e) {
            ctx.release();
            fail(m.id, e.message);
        }
        FileUtils.remove(enabling);
    }

    void fail (string id, string error) {
        warning("lumen-panel: extension %s: %s", id, error);
        set_status(id, "failed", error);
    }

    void set_status (string id, string state, string error) {
        var o = new Json.Object();
        o.set_string_member("state", state);
        o.set_string_member("error", error);
        status.set_object_member(id, o);
    }

    void write_status () {
        var root = new Json.Node(Json.NodeType.OBJECT);
        root.set_object(status);
        var gen = new Json.Generator() { root = root, pretty = true };
        try {
            gen.to_file(LumenCommon.Paths.extensions_status_json());
        } catch (GLib.Error e) {
            warning("lumen-panel: cannot write extension status: %s", e.message);
        }
    }
}
