// Apple Wi-Fi glyph: a weak signal dims the outer arcs to 25% rather than
// dropping them.
public class WifiArc {

    public static void draw (Gtk.Snapshot s, float cx, float cy,
                             int signal_pct, Gdk.RGBA fg) {
        int active = signal_pct >= 67 ? 3 : signal_pct >= 34 ? 2 : signal_pct >= 1 ? 1 : 0;

        const float K = 0.70710677f;   // cos/sin 45°
        float[] radii = { 4.0f, 8.0f, 12.0f };

        var stroke = new Gsk.Stroke (2.0f);
        stroke.set_line_cap (Gsk.LineCap.ROUND);

        for (int i = 0; i < 3; i++) {
            float sx = cx - K * radii[i];
            float ex = cx + K * radii[i];
            float ay = cy - K * radii[i];   // both endpoints sit above center

            var b = new Gsk.PathBuilder ();
            b.move_to (sx, ay);
            // Minor arc bulging over the top (positive sweep, y-down).
            b.svg_arc_to (radii[i], radii[i], 0f, false, true, ex, ay);

            var col = fg;
            col.alpha = (i < active) ? fg.alpha : fg.alpha * 0.25f;
            s.append_stroke (b.to_path (), stroke, col);
        }

        var dot = new Gsk.PathBuilder ();
        var c = Graphene.Point ();
        c.init (cx, cy);
        dot.add_circle (c, 1.6f);
        s.append_fill (dot.to_path (), Gsk.FillRule.WINDING, fg);
    }
}
