namespace Lumen {

    public errordomain CompileError { VALAC_MISSING, FAILED, BAD_TYPES }

    // Compiles a user extension's *.vala with valac into a cached .so.
    // STUB — implemented in a later task.
    public class Compiler : GLib.Object {
        public string cache_dir { get; construct; }
        public string vapidir { get; construct; }
        public string pkg_config_path { get; construct; }

        public Compiler (string cache_dir, string vapidir, string pkg_config_path) {
            GLib.Object (cache_dir: cache_dir, vapidir: vapidir, pkg_config_path: pkg_config_path);
        }

        public string cache_key (Manifest m) throws GLib.Error {
            throw new CompileError.FAILED ("not implemented");
        }

        public string so_path (Manifest m) throws GLib.Error {
            throw new CompileError.FAILED ("not implemented");
        }

        public async string build (Manifest m, GLib.Cancellable? cancellable = null) throws GLib.Error {
            throw new CompileError.FAILED ("not implemented");
        }
    }
}
