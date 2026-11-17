namespace LumenDrawer {

    public class DrawerConfig {
        public static int cols     = 6;
        public static int rows     = 4;
        public static int per_page = 24;

        // Shared by grid pages and SearchResults so tiles land on the same cells.
        public static int margin_x = 200;
        public static int margin_y = 130;

        public static void load() {
            var path = LumenCommon.Paths.drawer_ini();
            int v = LumenCommon.Ini.get_int(path, "drawer", "grid.cols", -1);
            if (v > 0) cols = v;
            v = LumenCommon.Ini.get_int(path, "drawer", "grid.rows", -1);
            if (v > 0) rows = v;
            per_page = cols * rows;

            // One value for all edges; unset keeps the asymmetric defaults.
            v = LumenCommon.Ini.get_int(path, "drawer", "grid.margin", -1);
            if (v >= 0) { margin_x = v; margin_y = v; }
        }
    }
}
