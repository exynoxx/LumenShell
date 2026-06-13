using Gtk;

/* Win+P-style display-mode picker: a centered panel of icon+label tiles laid
 * out side by side, with a rounded highlight behind the selected one. Driven
 * entirely from outside (the wayfire-display-switch plugin advances the
 * selection on each Super+P tap); this widget only renders state. */
public class Selector : Gtk.Box {

    // Fixed metrics so the selection highlight can be placed by arithmetic in
    // snapshot() rather than querying child allocations (which aren't valid
    // until after layout). `inner`'s margins act as the panel padding, exactly
    // like Pill's `inner` box — so the first tile sits at {PAD, PAD}.
    private const int PAD    = 18;   // panel padding around the tile row
    private const int TILE_W = 124;
    private const int TILE_H = 104;
    private const int SP     = 12;   // gap between tiles

    private Gtk.Box     inner;
    private Gtk.Box[]   tiles = {};
    private int         selected = 0;
    private int         count    = 0;

    // Pointer hooks: hovering a tile moves the highlight, clicking applies it.
    public signal void hovered(int index);
    public signal void chosen(int index);

    public Selector() {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

        inner = new Gtk.Box(Gtk.Orientation.HORIZONTAL, SP);
        inner.margin_start  = PAD;
        inner.margin_end    = PAD;
        inner.margin_top    = PAD;
        inner.margin_bottom = PAD;
        append(inner);
    }

    public void set_items(string[] icons, string[] labels, int sel) {
        int n = int.min(icons.length, labels.length);

        if (n != count) {
            // Tile count changed (e.g. external display (un)plugged): rebuild.
            Gtk.Widget? c = inner.get_first_child();
            while (c != null) {
                Gtk.Widget? next = c.get_next_sibling();
                inner.remove(c);
                c = next;
            }
            tiles = {};
            for (int i = 0; i < n; i++) {
                var tile = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
                tile.set_size_request(TILE_W, TILE_H);
                tile.set_halign(Gtk.Align.CENTER);
                tile.set_valign(Gtk.Align.CENTER);

                var img = new Gtk.Image.from_icon_name(icons[i]);
                img.pixel_size = 46;
                img.set_halign(Gtk.Align.CENTER);
                img.set_vexpand(true);
                img.set_valign(Gtk.Align.CENTER);
                tile.append(img);

                var lbl = new Gtk.Label(labels[i]);
                lbl.set_halign(Gtk.Align.CENTER);
                lbl.set_valign(Gtk.Align.END);
                lbl.set_justify(Gtk.Justification.CENTER);
                lbl.set_wrap(true);
                lbl.set_max_width_chars(12);
                tile.append(lbl);

                int idx = i;
                var motion = new Gtk.EventControllerMotion();
                motion.enter.connect((x, y) => { hovered(idx); });
                tile.add_controller(motion);

                var click = new Gtk.GestureClick();
                click.released.connect((n, x, y) => { chosen(idx); });
                tile.add_controller(click);

                inner.append(tile);
                tiles += tile;
            }
            count = n;
        } else {
            // Same shape: just refresh icon/label text in place.
            for (int i = 0; i < n; i++) {
                var img = (Gtk.Image) tiles[i].get_first_child();
                img.set_from_icon_name(icons[i]);
                var lbl = (Gtk.Label) img.get_next_sibling();
                lbl.set_text(labels[i]);
            }
        }

        selected = sel.clamp(0, (count > 0) ? count - 1 : 0);
        queue_draw();
    }

    public override void snapshot(Gtk.Snapshot s) {
        int w = get_width();
        int h = get_height();

        var bg_rect = Graphene.Rect();
        bg_rect.init(0f, 0f, (float) w, (float) h);
        var rr = Gsk.RoundedRect();
        rr.init_from_rect(bg_rect, 26f);
        s.push_rounded_clip(rr);
        s.append_color(Theme.background, bg_rect);
        s.pop();

        if (count > 0 && selected >= 0 && selected < count) {
            float x = (float) PAD + selected * (float) (TILE_W + SP);
            var hl_rect = Graphene.Rect();
            hl_rect.init(x, (float) PAD, (float) TILE_W, (float) TILE_H);
            var hrr = Gsk.RoundedRect();
            hrr.init_from_rect(hl_rect, 16f);

            // A translucent wash of the accent (progress fill) reads as
            // "selected" without fighting the white symbolic icon on top.
            Gdk.RGBA hl = Theme.progress_fill;
            hl.alpha = 0.22f;

            s.push_rounded_clip(hrr);
            s.append_color(hl, hl_rect);
            s.pop();
        }

        base.snapshot(s);
    }
}
