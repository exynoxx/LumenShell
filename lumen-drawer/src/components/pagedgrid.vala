public class PagedGrid : Gtk.Box {

    public int page_count { get; private set; }

    public signal void page_changed(int page);

    private Adw.Carousel carousel;
    private int active_page = 0;

    public PagedGrid(AppEntry[] apps) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        hexpand = true;
        vexpand = true;
        // Off-screen pages must never bleed past the viewport mid-slide.
        overflow = Gtk.Overflow.HIDDEN;

        carousel = new Adw.Carousel() {
            hexpand = true,
            vexpand = true,
        };
        // Also fires for our own scroll_to(); filtered via active_page.
        carousel.page_changed.connect(on_carousel_page_changed);

        int per_page = LumenDrawer.DrawerConfig.per_page;
        page_count = (apps.length + per_page - 1) / per_page;
        if (page_count < 1) page_count = 1;
        for (int p = 0; p < page_count; p++) carousel.append(build_page(apps, p));

        append(carousel);
    }

    private void on_carousel_page_changed(uint index) {
        if ((int) index == active_page) return;
        active_page = (int) index;
        page_changed(active_page);
    }

    public void reset_to_first_page() {
        scroll_to_page(0, false);
    }

    public void next_page() {
        scroll_to_page(active_page + 1, true);
    }

    public void prev_page() {
        scroll_to_page(active_page - 1, true);
    }

    public void goto_page(int page) {
        scroll_to_page(page, true);
    }

    private void scroll_to_page(int page, bool animate) {
        if (page < 0 || page >= page_count || page == active_page) return;
        // Announce up front so the dots track the keypress, not the animation end.
        active_page = page;
        page_changed(page);
        carousel.scroll_to(carousel.get_nth_page(page), animate);
    }

    private Gtk.Widget build_page(AppEntry[] apps, int page_index) {
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

        int start = page_index * per_page;
        for (int i = 0; i < per_page; i++) {
            int idx = start + i;
            if (idx >= apps.length) break;

            var tile = new AppTile();
            tile.bind(apps[idx]);
            grid.attach(tile, i % cols, i / cols, 1, 1);
        }

        var page = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
            hexpand       = true,
            vexpand       = true,
            halign        = Gtk.Align.FILL,
            valign        = Gtk.Align.FILL,
            margin_start  = LumenDrawer.DrawerConfig.margin_x,
            margin_end    = LumenDrawer.DrawerConfig.margin_x,
            margin_top    = LumenDrawer.DrawerConfig.margin_y,
            margin_bottom = LumenDrawer.DrawerConfig.margin_y,
        };
        page.append(grid);
        return page;
    }
}
