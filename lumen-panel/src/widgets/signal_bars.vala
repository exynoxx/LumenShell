using Gtk;

// Drawing the bars in a snapshot() override is cheaper than building five
// Gtk widgets per row.
public class SignalBars : Gtk.Widget {

    const int BAR_COUNT = 5;
    const int BAR_WIDTH = 3;
    const int BAR_GAP   = 2;
    const int MIN_H     = 4;
    const int MAX_H     = 16;

    int signal_pct;

    public SignalBars (int signal_pct) {
        this.signal_pct = int.max(0, int.min(100, signal_pct));
        set_size_request(BAR_COUNT * BAR_WIDTH + (BAR_COUNT - 1) * BAR_GAP, MAX_H);
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        int active = (int) Math.ceil(signal_pct / 100.0 * BAR_COUNT);
        var rgba_on  = Gdk.RGBA();  rgba_on.parse("white");
        var rgba_off = Gdk.RGBA();  rgba_off.parse("rgba(255,255,255,0.20)");

        int total_w = BAR_COUNT * BAR_WIDTH + (BAR_COUNT - 1) * BAR_GAP;
        int x0 = (get_width() - total_w) / 2;
        int y_bottom = (get_height() + MAX_H) / 2;

        for (int i = 0; i < BAR_COUNT; i++) {
            int h = MIN_H + (MAX_H - MIN_H) * i / (BAR_COUNT - 1);
            var rect = Graphene.Rect();
            rect.init(x0 + i * (BAR_WIDTH + BAR_GAP), y_bottom - h, BAR_WIDTH, h);
            snapshot.append_color(i < active ? rgba_on : rgba_off, rect);
        }
    }
}
