namespace Lumen {

    public errordomain CompileError { VALAC_MISSING, FAILED, BAD_TYPES }

    // Compiles a user extension's *.vala with valac into a cached .so.
    public class Compiler : GLib.Object {
        public string cache_dir { get; construct; }
        public string vapidir { get; construct; }
        public string pkg_config_path { get; construct; }

        static string? valac_version = null;

        public Compiler (string cache_dir, string vapidir, string pkg_config_path) {
            GLib.Object (cache_dir: cache_dir, vapidir: vapidir, pkg_config_path: pkg_config_path);
        }

        // Hash of everything that affects the binary: sources, manifest, the
        // API vapi itself and the compiler version.
        public string cache_key (Manifest m) throws GLib.Error {
            var sum = new Checksum (ChecksumType.SHA256);
            foreach (var name in source_names (m.dir, true)) {
                uint8[] data;
                FileUtils.get_data (Path.build_filename (m.dir, name), out data);
                sum.update ((uchar[]) name.to_utf8 (), name.length + 1);
                sum.update (data, data.length);
            }
            sum.update ((uchar[]) API_VERSION.to_string ().to_utf8 (), -1);
            uint8[] vapi;
            FileUtils.get_data (Path.build_filename (vapidir, "lumen-ext-1.vapi"), out vapi);
            sum.update (vapi, vapi.length);
            if (valac_version == null) {
                if (Environment.find_program_in_path ("valac") == null)
                    throw new CompileError.VALAC_MISSING ("valac not found in PATH");
                Process.spawn_command_line_sync ("valac --version", out valac_version);
            }
            sum.update ((uchar[]) valac_version.to_utf8 (), -1);
            return sum.get_string ().substring (0, 16);
        }

        public string so_path (Manifest m) throws GLib.Error {
            return Path.build_filename (cache_dir, "%s-%s.so".printf (m.id, cache_key (m)));
        }

        public async string build (Manifest m, GLib.Cancellable? cancellable = null) throws GLib.Error {
            var target = so_path (m);
            if (FileUtils.test (target, FileTest.EXISTS)) return target;

            DirUtils.create_with_parents (cache_dir, 0700);
            // Inside cache_dir so the final rename stays on one filesystem.
            var tmp = DirUtils.mkdtemp (Path.build_filename (cache_dir, ".build-XXXXXX"));
            var tmp_so = Path.build_filename (tmp, m.id + ".so");
            try {
                string[] argv = { "valac", "--vapidir=" + vapidir, "--pkg=lumen-ext-1",
                                  // --library: no main() required; writes <id>.vapi into tmp.
                                  "--library=" + m.id };
                foreach (var p in m.packages) argv += "--pkg=" + p;
                argv += "-X"; argv += "-shared";
                argv += "-X"; argv += "-fPIC";
                argv += "-X"; argv += "-O2";
                argv += "-X"; argv += "-w";
                argv += "-o"; argv += tmp_so;
                foreach (var name in source_names (m.dir, false))
                    argv += Path.build_filename (m.dir, name);

                yield run (argv, tmp, cancellable);

                // Every registered GType must live in the extension's own
                // namespace, or two extensions could clash on a global type
                // name. Full symtab: internal classes have hidden get_type
                // symbols but still register a global GType name.
                var syms = yield run ({ "nm", "--defined-only", tmp_so }, tmp, cancellable);
                string[] bad = {};
                foreach (var line in syms.split ("\n")) {
                    var sym = line.strip ();
                    sym = sym.substring (sym.last_index_of_char (' ') + 1);   // "<addr> T <name>"
                    if (sym.has_suffix ("_get_type") && !sym.has_prefix (m.symbol_prefix ()))
                        bad += sym;
                }
                if (bad.length > 0)
                    throw new CompileError.BAD_TYPES (
                        "types outside namespace %s: %s — put every type in `namespace %s { … }`",
                        m.type_namespace (), string.joinv (", ", bad), m.type_namespace ());

                FileUtils.rename (tmp_so, target);
            } finally {
                FileUtils.unlink (tmp_so);
                FileUtils.unlink (Path.build_filename (tmp, m.id + ".vapi"));
                DirUtils.remove (tmp);
            }

            // Drop stale builds of this extension.
            var dir = Dir.open (cache_dir);
            var keep = Path.get_basename (target);
            string? name;
            while ((name = dir.read_name ()) != null)
                if (name.has_prefix (m.id + "-") && name.has_suffix (".so") && name != keep)
                    FileUtils.unlink (Path.build_filename (cache_dir, name));
            return target;
        }

        // *.vala / *.vapi (plus manifest.json when hashing), sorted.
        static string[] source_names (string dir, bool with_manifest) throws GLib.Error {
            var names = new GLib.GenericArray<string> ();
            var d = Dir.open (dir);
            string? name;
            while ((name = d.read_name ()) != null)
                if (name.has_suffix (".vala") || name.has_suffix (".vapi")
                    || (with_manifest && name == "manifest.json"))
                    names.add (name);
            names.sort (strcmp);
            return names.data;
        }

        // Runs argv; returns stdout, or throws FAILED with stderr on nonzero exit.
        async string run (string[] argv, string cwd, Cancellable? cancellable) throws GLib.Error {
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            launcher.set_cwd (cwd);
            var old = Environment.get_variable ("PKG_CONFIG_PATH");
            launcher.setenv ("PKG_CONFIG_PATH",
                             old != null && old != "" ? pkg_config_path + ":" + old : pkg_config_path, true);
            var proc = launcher.spawnv (argv);
            string out_, err;
            yield proc.communicate_utf8_async (null, cancellable, out out_, out err);
            if (proc.get_exit_status () != 0) {
                err = (err ?? "").strip ();
                if (err.length > 4096) err = err.substring (0, 4096);
                throw new CompileError.FAILED ("%s", err);
            }
            return out_ ?? "";
        }
    }
}
