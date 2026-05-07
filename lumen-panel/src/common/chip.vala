using DrawKit;

/**
 * UiChip — a rounded-rect badge: coloured background + single text label.
 *
 * The chip auto-sizes its width from the text (lazily cached).
 * Callers set position via set_bounds() after querying get_width().
 */
public class UiChip : GLib.Object {

    public Color bg_color   = Color(){r=0.11f, g=0.13f, b=0.19f, a=1f};
    public Color text_color;
    public float text_size  = 12.5f;
    public float radius     = 12f;

    private string _text    = "";
    private int    _tw      = -1;   // cached text width, -1 = dirty

    private int rx;
    private int ry;
    private int rw;
    private int rh;

    public void set_text(string t) {
        if (t == _text) return;
        _text = t;
        _tw   = -1;
    }

    public string get_text() { return _text; }

    /** Pixel width of the chip (text + horizontal padding). Queries ctx once per text change. */
    public int get_width(Context ctx) {
        if (_tw < 0) _tw = ctx.width_of(_text, text_size);
        return _tw + 20;
    }

    public void set_bounds(int x, int y, int w, int h) {
        rx = x;  ry = y;  rw = w;  rh = h;
    }

    public void render(Context ctx) {
        if (_tw < 0) _tw = ctx.width_of(_text, text_size);
        ctx.draw_rect_rounded(rx, ry, rw, rh, radius, bg_color);
        pdt(ctx, _text, rx + 10, ry + (rh - (int)text_size) / 2, text_size, text_color);
    }
}
