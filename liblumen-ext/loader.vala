namespace Lumen {

    public errordomain LoadError { OPEN, NO_ENTRY }

    [CCode (has_target = false)]
    delegate Extension EntryFunc ();

    public class Loader : GLib.Object {
        // One Manifest per <dir>/<id>/manifest.json; later dirs override earlier
        // by id; invalid manifests are skipped with a warning. Sorted by id.
        public static GLib.GenericArray<Manifest> discover (string[] dirs) {
            var by_id = new HashTable<string, Manifest> (str_hash, str_equal);
            foreach (var dir in dirs) {
                Dir d;
                try { d = Dir.open (dir); } catch (FileError e) { continue; }
                string? name;
                while ((name = d.read_name ()) != null) {
                    var sub = Path.build_filename (dir, name);
                    if (!FileUtils.test (Path.build_filename (sub, "manifest.json"), FileTest.IS_REGULAR))
                        continue;
                    try {
                        var m = Manifest.load (sub);
                        by_id[m.id] = m;
                    } catch (GLib.Error e) {
                        warning ("extension %s: %s", sub, e.message);
                    }
                }
            }
            var out_ = new GLib.GenericArray<Manifest> ();
            foreach (var m in by_id.get_values ()) out_.add (m);
            out_.sort ((a, b) => strcmp (a.id, b.id));
            return out_;
        }

        // dlopen + lumen_extension_new(); the module is made resident.
        public static Extension load (string so_path) throws LoadError {
            var module = Module.open (so_path, ModuleFlags.LAZY | ModuleFlags.LOCAL);
            if (module == null) throw new LoadError.OPEN ("%s", Module.error ());
            void* sym;
            if (!module.symbol ("lumen_extension_new", out sym) || sym == null)
                throw new LoadError.NO_ENTRY ("%s: no lumen_extension_new()", so_path);
            module.make_resident ();
            return ((EntryFunc) sym) ();
        }
    }
}
