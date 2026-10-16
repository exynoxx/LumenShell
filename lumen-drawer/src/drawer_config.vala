namespace LumenDrawer {

    public class DrawerConfig {
        public static int cols     = 6;
        public static int rows     = 4;
        public static int per_page = 24;

        // Shared by grid pages and SearchResults so tiles land on the same cells.
        public static int margin_x = 200;
        public static int margin_y = 130;

        public static void load() {
            var kf = new KeyFile();
            try {
                kf.load_from_file(LumenCommon.Paths.drawer_ini(), KeyFileFlags.NONE);
            } catch (Error e) {
                return;   // no file yet, or unreadable: the defaults stand
            }

            int v = read_int(kf, "grid.cols");
            if (v > 0) cols = v;
            v = read_int(kf, "grid.rows");
            if (v > 0) rows = v;
            per_page = cols * rows;

            // One value for all edges; unset keeps the asymmetric defaults.
            v = read_int(kf, "grid.margin");
            if (v >= 0) { margin_x = v; margin_y = v; }
        }

        // -1 = absent or not an integer.
        private static int read_int(KeyFile kf, string key) {
            try {
                return kf.get_integer("drawer", key);
            } catch (Error e) {
                return -1;
            }
        }
    }
}
