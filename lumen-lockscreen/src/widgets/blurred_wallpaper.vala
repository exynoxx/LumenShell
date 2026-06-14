using Gtk;

// BlurredWallpaper — produces the frosted backdrop the lock card sits on.
//
// v1: rather than a live wlr-screencopy of the desktop (which shared GDK's
// Wayland display and crashed the daemon on every lock), we take the
// configured wallpaper image, blur it ONCE through GSK, and cache the
// resulting texture. Every lock — on every monitor, for the whole session —
// reuses that one texture, so the costly blur runs at most once per wallpaper.
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

    // Wallpaper source, in priority order:
    //   1. lumen-shell/wallpaper.ini  [wallpaper] image  — set via lumen-settings
    //   2. wf-shell.ini               [background] image — what wf-background
    //      actually renders on the desktop (the common case)
    //   3. the lockscreen theme's background-image
    private static string resolve_path() {
        var cfg = Environment.get_user_config_dir();
        string? p;

        p = read_ini_key(cfg + "/lumen-shell/wallpaper.ini", "wallpaper", "image");
        if (usable(p)) return (!) p;

        p = read_ini_key(cfg + "/wf-shell.ini", "background", "image");
        if (usable(p)) return (!) p;

        if (usable(Theme.background_image)) return Theme.background_image;
        return "";
    }

    private static bool usable(string? path) {
        return path != null && path != "" && FileUtils.test(path, FileTest.EXISTS);
    }

    // Minimal section-aware reader for `[section] key = <value>` — avoids
    // pulling a full INI parser into the lockscreen.
    private static string? read_ini_key(string path, string section, string key) {
        string contents;
        try {
            if (!FileUtils.get_contents(path, out contents)) return null;
        } catch (Error e) { return null; }

        bool in_section = false;
        foreach (string raw in contents.split("\n")) {
            string line = raw.strip();
            if (line.has_prefix("[") && line.has_suffix("]")) {
                in_section = (line.substring(1, line.length - 2).strip() == section);
                continue;
            }
            if (!in_section) continue;
            int eq = line.index_of("=");
            if (eq < 0) continue;
            if (line.substring(0, eq).strip() == key)
                return line.substring(eq + 1).strip();
        }
        return null;
    }

    // Render the image through a GSK blur into a texture. We crop a blur-radius
    // border off every side so the edge fade (the blur sampling past the image
    // into transparency) never shows; the backdrop then covers the screen with
    // what remains.
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

        // render_texture() on the GL renderer hands back a GL-backed texture
        // tied to THIS renderer's GL context. Once we unrealize() below, that
        // context dies and the texture renders black (and only flickers into
        // view for a frame when the dead context is briefly touched during
        // unlock teardown). Copy the pixels into a self-contained CPU texture
        // BEFORE unrealizing so the cached backdrop survives the renderer.
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
