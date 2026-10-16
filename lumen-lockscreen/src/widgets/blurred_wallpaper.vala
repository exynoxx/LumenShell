using Gtk;

public class BlurredWallpaper : GLib.Object {

    private static Gdk.Texture? cached     = null;
    private static string        cached_key = "";

    // The blurred wallpaper texture, or null when no wallpaper is configured /
    // readable — the backdrop then falls back to a solid scrim.
    public static Gdk.Texture? get_texture() {
        string path = resolve_path();
        if (path == "") return null;

        // Key the cache on path + mtime so editing the wallpaper invalidates it.
        string key = path;
        Posix.Stat st;
        if (Posix.stat(path, out st) == 0)
            key = "%s:%lld".printf(path, (int64) st.st_mtime);

        if (cached != null && cached_key == key) return cached;

        var tex = blur(path);
        if (tex != null) {
            cached     = tex;
            cached_key = key;
        }
        return tex;
    }

    // wallpaper.ini → wf-shell.ini (what wf-background renders) → theme image.
    private static string resolve_path() {
        var cfg = Environment.get_user_config_dir();
        string? p;

        p = read_ini_key(LumenCommon.Paths.wallpaper_ini(), "wallpaper", "image");
        if (usable(p)) return (!) p;

        p = read_ini_key(cfg + "/wf-shell.ini", "background", "image");
        if (usable(p)) return (!) p;

        if (usable(Theme.background_image)) return Theme.background_image;
        return "";
    }

    private static bool usable(string? path) {
        return path != null && path != "" && FileUtils.test(path, FileTest.EXISTS);
    }

    // A missing file, a missing group/key or a syntax error all mean "not
    // configured here" — fall through to the next source.
    private static string? read_ini_key(string path, string section, string key) {
        var kf = new KeyFile();
        try {
            kf.load_from_file(path, KeyFileFlags.NONE);
            return kf.get_string(section, key);
        } catch (Error e) {
            return null;
        }
    }

    // Crops a blur-radius border off every side so the edge fade (blur sampling
    // into transparency) never shows.
    private static Gdk.Texture? blur(string path) {
        Gdk.Texture src;
        try {
            src = Gdk.Texture.from_filename(path);
        } catch (Error e) {
            warning("lumen-lockscreen: cannot load wallpaper %s: %s", path, e.message);
            return null;
        }

        float w = (float) src.get_width();
        float h = (float) src.get_height();
        float r = (float) Theme.blur_radius;
        if (w <= 2 * r || h <= 2 * r) r = 0;   // tiny image: don't crop it away

        var snap = new Gtk.Snapshot();
        snap.push_blur((double) Theme.blur_radius);
        Graphene.Rect full = {};
        full.init(0, 0, w, h);
        snap.append_texture(src, full);
        snap.pop();

        var node = snap.to_node();
        if (node == null) return null;

        var renderer = realize_renderer();
        if (renderer == null) return null;

        Graphene.Rect viewport = {};
        viewport.init(r, r, w - 2 * r, h - 2 * r);
        var tex = renderer.render_texture(node, viewport);

        // The GL texture dies with this renderer's context (renders black), so
        // copy to a CPU texture BEFORE unrealize().
        int tw = tex.get_width();
        int th = tex.get_height();
        var dl = new Gdk.TextureDownloader(tex);
        dl.set_format(Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED);
        size_t stride;
        var bytes = dl.download_bytes(out stride);
        renderer.unrealize();

        return new Gdk.MemoryTexture(tw, th,
                                     Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED,
                                     bytes, stride);
    }

    // Offscreen renderer for the one-shot blur: GL preferred, Cairo fallback.
    private static Gsk.Renderer? realize_renderer() {
        var display = Gdk.Display.get_default();
        if (display == null) return null;

        Gsk.Renderer gl = new Gsk.GLRenderer();
        try {
            gl.realize_for_display(display);
            return gl;
        } catch (Error e) {
            warning("lumen-lockscreen: GL renderer unavailable (%s); using Cairo",
                    e.message);
        }

        Gsk.Renderer cairo = new Gsk.CairoRenderer();
        try {
            cairo.realize_for_display(display);
            return cairo;
        } catch (Error e) {
            warning("lumen-lockscreen: no usable renderer for wallpaper blur: %s",
                    e.message);
            return null;
        }
    }
}
