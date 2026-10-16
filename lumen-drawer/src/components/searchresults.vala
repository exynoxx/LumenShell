public class SearchResults : Gtk.Box {

    private AppTile[] tiles;
    private int active_count;

    public SearchResults() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class("search-results");

        // Same margins and grid as PagedGrid so tiles land on the same cells.
        set_hexpand(true);
        set_vexpand(true);
        set_halign(Gtk.Align.FILL);
        set_valign(Gtk.Align.FILL);
        margin_start  = LumenDrawer.DrawerConfig.margin_x;
        margin_end    = LumenDrawer.DrawerConfig.margin_x;
        margin_top    = LumenDrawer.DrawerConfig.margin_y;
        margin_bottom = LumenDrawer.DrawerConfig.margin_y;

        var grid = new Gtk.Grid() {
            halign             = Gtk.Align.FILL,
            valign             = Gtk.Align.FILL,
            hexpand            = true,
            vexpand            = true,
            column_homogeneous = true,
            row_homogeneous    = true,
        };
        grid.add_css_class("page");

        int per_page = LumenDrawer.DrawerConfig.per_page;
        int cols     = LumenDrawer.DrawerConfig.cols;

        tiles = new AppTile[per_page];
        for (int i = 0; i < per_page; i++) {
            tiles[i] = new AppTile();
            // Opacity 0 + insensitive keeps the cell allocated but inert.
            tiles[i].set_opacity(0);
            tiles[i].set_sensitive(false);
            grid.attach(tiles[i], i % cols, i / cols, 1, 1);
        }
        append(grid);
        active_count = 0;
    }

    public void update(AppEntry[] apps, int size) {
        int new_count = int.min(size, tiles.length);
        for (int i = 0; i < new_count; i++) {
            tiles[i].bind(apps[i]);
            if (i >= active_count) {
                tiles[i].set_opacity(1);
                tiles[i].set_sensitive(true);
            }
        }
        for (int i = new_count; i < active_count; i++) {
            tiles[i].unbind();
            tiles[i].set_opacity(0);
            tiles[i].set_sensitive(false);
        }
        active_count = new_count;
    }

    public bool launch_at(int index) {
        if (index < 0 || index >= active_count) return false;
        if (tiles[index].entry == null) return false;
        tiles[index].entry.launch();
        return true;
    }

    public void launch_first() {
        launch_at(0);
    }
}
