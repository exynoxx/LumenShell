namespace Lumen {

    public errordomain LoadError { OPEN, NO_ENTRY }

    // STUB — implemented in a later task.
    public class Loader : GLib.Object {
        // One Manifest per <dir>/<id>/manifest.json; later dirs override earlier
        // by id; invalid manifests are skipped with a warning.
        public static GLib.GenericArray<Manifest> discover (string[] dirs) {
            return new GLib.GenericArray<Manifest> ();
        }

        // dlopen + lumen_extension_new(); the module is made resident.
        public static Extension load (string so_path) throws LoadError {
            throw new LoadError.OPEN ("not implemented");
        }
    }
}
