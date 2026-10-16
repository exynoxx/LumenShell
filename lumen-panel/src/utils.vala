// Resolved metadata for one app_id. `info` is null when no .desktop file could
// be found; `name` then falls back to the app_id itself.
public struct AppMetadata {
    public string name;
    public DesktopAppInfo? info;
}

public class Utils {

    public static string THEME_FILE {
        owned get {
            return LumenCommon.Paths.theme_file(
                "LUMEN_THEME_FILE", "theme.json",
                "lumen-panel/default-theme.json");
        }
    }

    public static Gdk.RGBA rgba (float r, float g, float b, float a) {
        var c = Gdk.RGBA();
        c.red = r; c.green = g; c.blue = b; c.alpha = a;
        return c;
    }

    // Fill a (optionally rounded) rectangle with a solid color. radius <= 0
    // appends the color straight, with no clip node.
    public static void fill_rounded (Gtk.Snapshot s, float x, float y, float w, float h,
                                     float radius, Gdk.RGBA color) {
        var rect = Graphene.Rect();
        rect.init(x, y, w, h);
        if (radius <= 0) {
            s.append_color(color, rect);
            return;
        }
        var rr = Gsk.RoundedRect();
        rr.init_from_rect(rect, radius);
        s.push_rounded_clip(rr);
        s.append_color(color, rect);
        s.pop();
    }

    public static Pango.Layout text_layout (Gtk.Widget w, string text, double size_pt,
                                            Pango.Weight weight = Pango.Weight.NORMAL) {
        var layout = w.create_pango_layout(text);
        var attrs = new Pango.AttrList();
        attrs.insert(Pango.AttrSize.new_absolute((int) (size_pt * Pango.SCALE)));
        attrs.insert(Pango.attr_weight_new(weight));
        layout.set_attributes(attrs);
        return layout;
    }

    public static void draw_layout (Gtk.Snapshot s, Pango.Layout layout,
                                    float x, float y, Gdk.RGBA color) {
        var pt = Graphene.Point();
        pt.init(x, y);
        s.save();
        s.translate(pt);
        s.append_layout(layout, color);
        s.restore();
    }
    // Case-insensitive prefix match over the registered applications, for
    // app_ids whose case doesn't match the .desktop filename.
    static DesktopAppInfo? find_by_prefix (string app_id) {
        string needle = app_id.down();
        foreach (unowned AppInfo app in AppInfo.get_all()) {
            var desktop = app as DesktopAppInfo;
            if (desktop == null) continue;
            unowned string? id = desktop.get_id();
            if (id != null && id.down().has_prefix(needle)) return desktop;
        }
        return null;
    }

    // Resolve app metadata via GLib.DesktopAppInfo (which does the XDG search),
    // falling back to the fuzzy prefix match.
    public static AppMetadata load_app_metadata (string app_id) {
        AppMetadata m = { app_id, null };

        DesktopAppInfo? info = new DesktopAppInfo(app_id + ".desktop");
        if (info == null) info = find_by_prefix(app_id);
        if (info == null) return m;

        m.info = info;
        string? name = info.get_name();
        if (name != null && name != "") m.name = name;
        return m;
    }
}
