// Snapshot-drawn, not Gtk.Buttons: the frame is a fill the content is clipped
// inside, so there is no chrome container a real child could be packed into.

namespace LumenDesktop {

    public enum ChromeHit { NONE, PIN, CLOSE }

    public class ChromeButtons : GLib.Object {

        private const int MAX_SIZE = 20;   // button box at full size
        private const int MIN_SIZE = 12;   // below this the glyphs stop reading
        private const int PAD = 5;         // gap from the band's ends

        // False when the band is too small: no chrome rather than a smudge.
        public static bool layout(Cairo.RectangleInt band, bool with_close,
                                  out Cairo.RectangleInt pin,
                                  out Cairo.RectangleInt close) {
            pin = Cairo.RectangleInt() { x = 0, y = 0, width = 0, height = 0 };
            close = pin;

            int size = int.min(MAX_SIZE, band.height - 4);
            if (size < MIN_SIZE) return false;

            int need = with_close ? 2 * size + 3 * PAD : size + 2 * PAD;
            if (band.width < need) return false;

            int y = band.y + (band.height - size) / 2;
            pin = Cairo.RectangleInt() {
                x = band.x + PAD, y = y, width = size, height = size
            };
            if (with_close) {
                close = Cairo.RectangleInt() {
                    x = band.x + band.width - PAD - size, y = y,
                    width = size, height = size
                };
            }
            return true;
        }

        public static ChromeHit hit_test(Cairo.RectangleInt band, bool with_close,
                                         double px, double py) {
            Cairo.RectangleInt pin, close;
            if (!layout(band, with_close, out pin, out close)) return ChromeHit.NONE;
            if (contains(pin, px, py)) return ChromeHit.PIN;
            if (with_close && contains(close, px, py)) return ChromeHit.CLOSE;
            return ChromeHit.NONE;
        }

        public static void snapshot(Gtk.Snapshot s, Cairo.RectangleInt band,
                                    bool pinned, ChromeHit hover, Gdk.RGBA fg) {
            Cairo.RectangleInt pin, close;
            if (!layout(band, !pinned, out pin, out close)) return;

            draw_hover(s, pin, fg, hover == ChromeHit.PIN);
            draw_pin(s, pin, pinned, fg);

            if (!pinned) {
                draw_hover(s, close, fg, hover == ChromeHit.CLOSE);
                draw_close(s, close, fg);
            }
        }

        private static bool contains(Cairo.RectangleInt r, double x, double y) {
            return x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height;
        }

        private static void draw_hover(Gtk.Snapshot s, Cairo.RectangleInt r,
                                       Gdk.RGBA fg, bool on) {
            if (!on) return;
            var rect = Graphene.Rect();
            rect.init(r.x - 2, r.y - 2, r.width + 4, r.height + 4);
            var rr = Gsk.RoundedRect();
            rr.init_from_rect(rect, (r.width + 4) / 4.0f);
            var tint = fg;
            tint.alpha = fg.alpha * 0.18f;
            s.push_rounded_clip(rr);
            s.append_color(tint, rect);
            s.pop();
        }

        // Drawn in a 0..100 unit box; tilted 45° when unpinned.
        private static void draw_pin(Gtk.Snapshot s, Cairo.RectangleInt r,
                                     bool pinned, Gdk.RGBA fg) {
            float n = r.width;
            float u = n / 100.0f;

            s.save();
            s.translate({ r.x + n / 2.0f, r.y + n / 2.0f });
            if (!pinned) s.rotate(45.0f);
            s.translate({ -n / 2.0f, -n / 2.0f });

            var b = new Gsk.PathBuilder();
            b.add_circle({ 50 * u, 26 * u }, 18 * u);

            var bar = Graphene.Rect();
            bar.init(22 * u, 38 * u, 56 * u, 13 * u);
            var rr = Gsk.RoundedRect();
            rr.init_from_rect(bar, 5 * u);
            b.add_rounded_rect(rr);

            b.move_to(44 * u, 51 * u);
            b.line_to(56 * u, 51 * u);
            b.line_to(50 * u, 97 * u);
            b.close();

            s.append_fill(b.to_path(), Gsk.FillRule.WINDING, fg);
            s.restore();
        }

        private static void draw_close(Gtk.Snapshot s, Cairo.RectangleInt r,
                                       Gdk.RGBA fg) {
            float n = r.width;
            float m = n * 0.3f;

            var stroke = new Gsk.Stroke(float.max(1.5f, n * 0.11f));
            stroke.set_line_cap(Gsk.LineCap.ROUND);

            var b = new Gsk.PathBuilder();
            b.move_to(r.x + m, r.y + m);
            b.line_to(r.x + n - m, r.y + n - m);
            b.move_to(r.x + n - m, r.y + m);
            b.line_to(r.x + m, r.y + n - m);

            s.append_stroke(b.to_path(), stroke, fg);
        }
    }
}
