public const int GRID_COLS = 6;
public const int GRID_ROWS = 4;
public const int PER_PAGE = GRID_COLS * GRID_ROWS;

// Edge insets shared between PagedGrid pages and SearchResults so the two
// views land tiles on the same cells when toggling between them.
public const int PAGE_MARGIN_X = 200;
public const int PAGE_MARGIN_Y = 130;

public class PagedGrid : Gtk.Widget {

    public int active_page { get; private set; }
    public int page_count { get; private set; }

    public signal void page_changed(int page);

    private Gtk.Widget[] pages;

    // Slide animation: animates current_offset from page N*w to page M*w.
    // The two on-screen pages move together; pages outside the viewport are
    // culled in snapshot().
    private const double SLIDE_DURATION_S = 0.7;
    private float current_offset;
    private float slide_from_offset;
    private float slide_to_offset;
    private int64 slide_start_us;
    private uint  slide_tick_id;

    // Initial zoom-in animation. Mirrors drawkit's centered_zoom_marix —
    // grid starts scaled 10x around screen center (icons mostly off-screen)
    // and shrinks to 1x via ease-out-expo, giving the "rush in from +Z" feel.
    private const double ZOOM_DURATION_S = 0.7;
    private const float  ZOOM_FROM       = 10.0f;
    private float zoom_factor;
    private int64 zoom_start_us;
    private uint  zoom_tick_id;
    private bool  zoom_started;

    construct {
        set_overflow(Gtk.Overflow.HIDDEN);
        set_hexpand(true);
        set_vexpand(true);
        zoom_factor = ZOOM_FROM;
    }

    public PagedGrid(AppEntry[] apps) {
        page_count = (apps.length + PER_PAGE - 1) / PER_PAGE;
        if (page_count < 1) page_count = 1;

        pages = new Gtk.Widget[page_count];
        for (int p = 0; p < page_count; p++) {
            pages[p] = build_page(apps, p);
            pages[p].set_parent(this);
        }
        active_page = 0;
        current_offset = 0;
        slide_to_offset = 0;
    }

    public override void dispose() {
        if (slide_tick_id != 0) { remove_tick_callback(slide_tick_id); slide_tick_id = 0; }
        if (zoom_tick_id  != 0) { remove_tick_callback(zoom_tick_id);  zoom_tick_id  = 0; }
        if (pages != null) {
            for (int p = 0; p < pages.length; p++) {
                if (pages[p] != null) {
                    pages[p].unparent();
                    pages[p] = null;
                }
            }
        }
        base.dispose();
    }

    public override void map() {
        base.map();
        if (!zoom_started) {
            zoom_started = true;
            var clock = get_frame_clock();
            zoom_start_us = (clock != null) ? clock.get_frame_time() : GLib.get_monotonic_time();
            if (zoom_tick_id == 0) {
                zoom_tick_id = add_tick_callback(on_zoom_tick);
            }
        }
    }

    public override void measure(Gtk.Orientation orientation, int for_size,
                                 out int minimum, out int natural,
                                 out int minimum_baseline, out int natural_baseline) {
        int m = 0, n = 0;
        for (int p = 0; p < page_count; p++) {
            int pm, pn, mb, nb;
            pages[p].measure(orientation, for_size, out pm, out pn, out mb, out nb);
            m = int.max(m, pm);
            n = int.max(n, pn);
        }
        minimum = m;
        natural = n;
        minimum_baseline = -1;
        natural_baseline = -1;
    }

    public override void size_allocate(int width, int height, int baseline) {
        // Keep current_offset locked to the active page when allocation
        // changes (e.g. on monitor configure) and no slide is running.
        if (slide_tick_id == 0) {
            current_offset = active_page * (float) width;
            slide_to_offset = current_offset;
        }
        allocate_pages(width, height, baseline);
    }

    private void allocate_pages(int width, int height, int baseline) {
        // Each page is allocated at its real horizontal position via a
        // Gsk.Transform on allocate(). Using a real transform (instead of
        // translating only inside snapshot()) is what makes pointer picking
        // hit the visible tile: GTK's default pick walks children by their
        // allocation, so the transform must agree with what's on screen.
        float fw = (float) width;
        for (int p = 0; p < page_count; p++) {
            float page_x = p * fw - current_offset;
            var pt = Graphene.Point();
            pt.x = page_x; pt.y = 0f;
            Gsk.Transform? t = new Gsk.Transform().translate(pt);
            pages[p].allocate(width, height, baseline, t);
        }
    }

    public override void snapshot(Gtk.Snapshot s) {
        int w = get_width();
        int h = get_height();
        if (w <= 0 || h <= 0) return;

        bool zooming = zoom_factor > 1.0001f;

        if (zooming) {
            s.save();
            var c = Graphene.Point();
            c.x = w / 2.0f; c.y = h / 2.0f;
            s.translate(c);
            s.scale(zoom_factor, zoom_factor);
            var nc = Graphene.Point();
            nc.x = -w / 2.0f; nc.y = -h / 2.0f;
            s.translate(nc);
        }

        // Pages carry their own translate transform via allocate(), so
        // snapshot_child positions them correctly. overflow:HIDDEN clips
        // anything outside the viewport.
        for (int p = 0; p < page_count; p++) {
            snapshot_child(pages[p], s);
        }

        if (zooming) s.restore();
    }

    // Snap back to page 0 without animation. Used when the Kickoff daemon
    // re-shows the window — every open should land on the first page.
    public void reset_to_first_page() {
        if (slide_tick_id != 0) { remove_tick_callback(slide_tick_id); slide_tick_id = 0; }
        active_page = 0;
        page_changed(0);
        current_offset = 0;
        slide_to_offset = 0;
        queue_allocate();
    }

    // Replay the zoom-in intro. If the widget is still mapped (the daemon
    // path: window hidden then re-shown reuses the same allocation), map()
    // won't fire again, so kick off the tick callback directly.
    public void reset_intro() {
        if (zoom_tick_id != 0) { remove_tick_callback(zoom_tick_id); zoom_tick_id = 0; }
        zoom_factor = ZOOM_FROM;
        zoom_started = false;
        queue_draw();
        if (get_mapped()) {
            zoom_started = true;
            var clock = get_frame_clock();
            zoom_start_us = (clock != null) ? clock.get_frame_time() : GLib.get_monotonic_time();
            zoom_tick_id = add_tick_callback(on_zoom_tick);
        }
    }

    public void next_page() {
        if (active_page >= page_count - 1) return;
        active_page++;
        page_changed(active_page);
        start_slide_to(active_page * (float) get_width());
    }

    public void prev_page() {
        if (active_page <= 0) return;
        active_page--;
        page_changed(active_page);
        start_slide_to(active_page * (float) get_width());
    }

    private void start_slide_to(float target) {
        slide_from_offset = current_offset;
        slide_to_offset   = target;
        var clock = get_frame_clock();
        slide_start_us = (clock != null) ? clock.get_frame_time() : GLib.get_monotonic_time();
        if (slide_tick_id == 0) {
            slide_tick_id = add_tick_callback(on_slide_tick);
        }
    }

    private bool on_slide_tick(Gtk.Widget w, Gdk.FrameClock clock) {
        int64 now = clock.get_frame_time();
        double elapsed_s = (now - slide_start_us) / 1000000.0;
        double t = double.min(elapsed_s / SLIDE_DURATION_S, 1.0);
        double eased = ease_out_expo(t);
        current_offset = (float) (slide_from_offset + (slide_to_offset - slide_from_offset) * eased);
        // queue_allocate (not queue_draw) — pages are positioned via their
        // allocation transform, so the slide has to re-allocate to move.
        queue_allocate();
        if (t >= 1.0) {
            current_offset = slide_to_offset;
            slide_tick_id = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    private bool on_zoom_tick(Gtk.Widget w, Gdk.FrameClock clock) {
        int64 now = clock.get_frame_time();
        double elapsed_s = (now - zoom_start_us) / 1000000.0;
        double t = double.min(elapsed_s / ZOOM_DURATION_S, 1.0);
        double eased = ease_out_expo(t);
        zoom_factor = (float) (ZOOM_FROM + (1.0 - ZOOM_FROM) * eased);
        queue_draw();
        if (t >= 1.0) {
            zoom_factor = 1.0f;
            zoom_tick_id = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    private static double ease_out_expo(double k) {
        return (k >= 1.0) ? 1.0 : (1.0 - GLib.Math.pow(2.0, -10.0 * k));
    }

    private Gtk.Widget build_page(AppEntry[] apps, int page_index) {
        // Homogeneous fill so cells distribute the page area evenly — the
        // grid is as large as its margins allow, and each cell gets equal
        // space. Tiles are centered within their cells via AppTile's
        // halign/valign.
        var grid = new Gtk.Grid() {
            halign             = Gtk.Align.FILL,
            valign             = Gtk.Align.FILL,
            hexpand            = true,
            vexpand            = true,
            column_homogeneous = true,
            row_homogeneous    = true,
        };
        grid.add_css_class("page");

        int start = page_index * PER_PAGE;
        for (int i = 0; i < PER_PAGE; i++) {
            int idx = start + i;
            if (idx >= apps.length) break;

            var tile = new AppTile();
            tile.bind(apps[idx]);

            int row = i / GRID_COLS;
            int col = i % GRID_COLS;
            grid.attach(tile, col, row, 1, 1);
        }

        // Outer page: full bleed with edge margins matching drawkit's
        // PADDING_EDGES_X / PADDING_EDGES_Y. The grid then spans the area
        // inside those margins.
        var page = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
            hexpand       = true,
            vexpand       = true,
            halign        = Gtk.Align.FILL,
            valign        = Gtk.Align.FILL,
            margin_start  = PAGE_MARGIN_X,
            margin_end    = PAGE_MARGIN_X,
            margin_top    = PAGE_MARGIN_Y,
            margin_bottom = PAGE_MARGIN_Y,
        };
        page.append(grid);
        return page;
    }
}
