public class SearchResults : Gtk.Box {

    private AppTile[] tiles;
    private int active_count;

    public SearchResults() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class("search-results");

        // Mirror the main-page layout: full-bleed page with the same edge
        // margins, a homogeneous 6x4 Grid inside. Tiles occupy fixed cell
        // positions so the layout stays stable as results come and go.
        set_hexpand(true);
        set_vexpand(true);
        set_halign(Gtk.Align.FILL);
        set_valign(Gtk.Align.FILL);
        margin_start  = PAGE_MARGIN_X;
        margin_end    = PAGE_MARGIN_X;
        margin_top    = PAGE_MARGIN_Y;
        margin_bottom = PAGE_MARGIN_Y;

        var grid = new Gtk.Grid() {
            halign             = Gtk.Align.FILL,
            valign             = Gtk.Align.FILL,
            hexpand            = true,
            vexpand            = true,
            column_homogeneous = true,
            row_homogeneous    = true,
        };
        grid.add_css_class("page");

        tiles = new AppTile[PER_PAGE];
        for (int i = 0; i < PER_PAGE; i++) {
            tiles[i] = new AppTile();
            // Reserve the cell visually-empty until bound. Opacity 0 + not
            // sensitive keeps the allocation but hides icon/label and
            // prevents stray clicks.
            tiles[i].set_opacity(0);
            tiles[i].set_sensitive(false);
            int row = i / GRID_COLS;
            int col = i % GRID_COLS;
            grid.attach(tiles[i], col, row, 1, 1);
        }
        append(grid);
        active_count = 0;
    }

    public void update(Utils.AliasArray<AppEntry> apps, int size) {
        active_count = int.min(size, PER_PAGE);
        for (int i = 0; i < active_count; i++) {
            tiles[i].bind(apps[i]);
            tiles[i].set_opacity(1);
            tiles[i].set_sensitive(true);
        }
        for (int i = active_count; i < PER_PAGE; i++) {
            tiles[i].unbind();
            tiles[i].set_opacity(0);
            tiles[i].set_sensitive(false);
        }
    }

    public bool launch_at(int index) {
        if (index < 0 || index >= active_count) return false;
        if (tiles[index].entry == null) return false;
        tiles[index].entry.launch();
        return true;
    }

    public bool launch_first() {
        return launch_at(0);
    }
}
