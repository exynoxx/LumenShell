// Minimal foreign-toplevel watcher for lumen-desktop. We don't need the full
// per-window metadata that lumen-panel's ToplevelStore exposes — only the
// derived question "is some normal app window currently focused?". The blur
// fade animation hangs off the boolean transitions of that property.
//
// Bound to GTK's existing wl_display via wlhooks (same pattern as the panel),
// so there's no second Wayland connection.

public class DesktopToplevels : GLib.Object {

    // Fires on every meaningful focus event — both transitions of
    // `any_focused` AND focus moves between two real windows (id changes
    // while still `true`). The latter is what re-arms the blur when the
    // user launches an app and the freshly-mapped window steals focus
    // from the previously-focused one: from a boolean standpoint nothing
    // changed, but the desktop is now behind a different window and
    // wants to fade back in.
    public signal void focus_changed(bool any_focused);

    public bool any_focused { get; private set; default = false; }

    private GLib.HashTable<uint, bool> live =
        new GLib.HashTable<uint, bool>(GLib.direct_hash, GLib.direct_equal);
    private uint focused_id = 0;

    private static DesktopToplevels? _instance = null;
    public static DesktopToplevels instance {
        get { return _instance ?? (_instance = new DesktopToplevels()); }
    }

    public bool bind() {
        var gdk = Gdk.Display.get_default();
        if (!(gdk is Gdk.Wayland.Display)) {
            GLib.stderr.printf("DesktopToplevels: not running on Wayland\n");
            return false;
        }
        unowned Wl.Display wl = ((Gdk.Wayland.Display) gdk).get_wl_display();

        int rc = WLHooks.init_toplevel_with_display(wl);
        if (rc != 0) {
            GLib.stderr.printf("DesktopToplevels: init_toplevel_with_display failed (%d)\n", rc);
            return false;
        }

        WLHooks.register_on_window_new(on_new);
        WLHooks.register_on_window_rm(on_rm);
        WLHooks.register_on_window_focus(on_focus);
        return true;
    }

    private void on_new(uint id, string app_id, string title) {
        live.insert(id, true);
    }

    private void on_rm(uint id) {
        live.remove(id);
        if (id == focused_id) {
            focused_id = 0;
            set_focused(false);
        }
    }

    private void on_focus(uint id) {
        bool new_focused = live.contains(id);
        bool id_changed  = (id != focused_id);
        focused_id = id;

        if (any_focused != new_focused) {
            any_focused = new_focused;
            focus_changed(new_focused);
        } else if (new_focused && id_changed) {
            // Same boolean, different window — re-fire so the blur fades
            // back in after a wallpaper click that forced it out.
            focus_changed(true);
        }
    }

    private void set_focused(bool v) {
        if (any_focused == v) return;
        any_focused = v;
        focus_changed(v);
    }
}
