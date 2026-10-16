public class LumenProgressBar : Gtk.Widget {

    int _value = 0;

    public Gdk.RGBA track_color = Utils.rgba(0.10f, 0.11f, 0.16f, 1f);
    public Gdk.RGBA fill_color  = Utils.rgba(0.13f, 0.76f, 0.34f, 1f);
    public Gdk.RGBA text_color  = Utils.rgba(1f,    1f,    1f,    0.65f);

    public LumenProgressBar () {
        set_size_request(-1, 22);
        hexpand = true;
    }

    public void set_progress (int v) {
        v = int.max(0, int.min(100, v));
        if (v == _value) return;
        _value = v;
        queue_draw();
    }

    public override void snapshot (Gtk.Snapshot s) {
        int w = get_width();
        int h = get_height();
        if (w <= 0 || h <= 0) return;

        float radius = (float) int.min(h / 2, 12);

        Utils.fill_rounded(s, 0, 0, w, h, radius, track_color);

        int fill_w = (int) (w * _value / 100.0f);
        if (fill_w > 0) Utils.fill_rounded(s, 0, 0, fill_w, h, radius, fill_color);

        var layout = Utils.text_layout(this, "%d%%".printf(_value), 11);
        int tw, th;
        layout.get_pixel_size(out tw, out th);
        Utils.draw_layout(s, layout, w - tw - 8, (h - th) / 2, text_color);
    }
}
