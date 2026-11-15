// Strict junk tier: paths that never appear in any result list.
namespace LumenSearch {
    public class Junk {
        // Dotted dirs (.git, .cache, .local, ...) are caught by the leading-dot rule.
        const string[] JUNK_SEGMENTS = {
            "node_modules", "__pycache__", "target", "build", "dist", "vendor", "site-packages",
        };

        public static bool is_junk(string path, string home) {
            if (under(path, home + "/go/pkg") || under(path, home + "/.local/share/Trash"))
                return true;
            // Scan only below $HOME so a home under e.g. /x/build/ isn't junk.
            var rel = path.has_prefix(home + "/") ? path.substring(home.length + 1) : path;
            foreach (var seg in rel.split("/")) {
                if (seg.has_prefix(".")) return true;
                foreach (var j in JUNK_SEGMENTS) {
                    if (seg == j) return true;
                }
            }
            return false;
        }

        static bool under(string path, string dir) {
            return path == dir || path.has_prefix(dir + "/");
        }
    }
}
