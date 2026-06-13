using GLib;

// One running window. Backed by zwlr-foreign-toplevel-management-unstable-v1
// via wlhooks; the id is the same opaque uint32 wlhooks issues, which is what
// activate/close/minimize accept.
public class Toplevel : GLib.Object {
    public uint   id          { get; construct; }
    public string app_id      { get; set; }
    public string title       { get; set; }
    public bool   activated   { get; set; }
    // Connector name of the output this window is on ("" if unknown). Used for
    // per-monitor taskbar filtering.
    public string output      { get; set; default = ""; }

    public Toplevel (uint id, string app_id, string title) {
        GLib.Object(id: id);
        this.app_id    = app_id;
        this.title     = title;
        this.activated = false;
    }
}

// Live set of toplevels. Backed by wlhooks's foreign-toplevel callbacks on the
// GTK-owned wl_display.
public class ToplevelStore : GLib.Object {

    public signal void added   (Toplevel t);
    public signal void removed (uint id);
    public signal void focused (uint id);
    public signal void output_changed (uint id, string output);

    GLib.HashTable<uint, Toplevel> by_id =
        new GLib.HashTable<uint, Toplevel>(direct_hash, direct_equal);

    static ToplevelStore? _instance = null;
    public static ToplevelStore instance {
        get { return _instance ?? (_instance = new ToplevelStore()); }
    }

    // Bind once, after Gdk.Display is available (i.e. inside Application.activate).
    public bool bind () {
        var gdk = Gdk.Display.get_default();
        if (!(gdk is Gdk.Wayland.Display)) {
            stderr.printf("ToplevelStore: not running on Wayland\n");
            return false;
        }
        unowned Wl.Display wl = ((Gdk.Wayland.Display) gdk).get_wl_display();

        int rc = WLHooks.init_toplevel_with_display(wl);
        if (rc != 0) {
            stderr.printf("ToplevelStore: wlhooks_init_toplevel_with_display failed\n");
            return false;
        }

        WLHooks.register_on_window_new   (on_new);
        WLHooks.register_on_window_rm    (on_rm);
        WLHooks.register_on_window_focus (on_focus);
        WLHooks.register_on_window_output_changed (on_output);
        return true;
    }

    public void activate (uint id) { WLHooks.toplevel_activate_by_id(id); }
    public void close    (uint id) { WLHooks.toplevel_close_by_id(id);    }
    public void minimize (uint id) { WLHooks.toplevel_minimize_by_id(id); }

    public Toplevel? find (uint id)        { return by_id.lookup(id); }
    public List<unowned Toplevel> all ()   { return by_id.get_values(); }

    void on_new (uint id, string app_id, string title) {
        var t = new Toplevel(id, app_id, title);
        by_id.insert(id, t);
        added(t);
        stdout.printf("+ toplevel %u  app=%s  title=%s\n", id, app_id, title);
    }

    void on_rm (uint id) {
        by_id.remove(id);
        removed(id);
        stdout.printf("- toplevel %u\n", id);
    }

    void on_focus (uint id) {
        // Mark this one active, clear the rest. (wlhooks only emits focus for
        // the newly-activated window, so we have to clear siblings ourselves.)
        by_id.foreach((k, v) => v.activated = (k == id));
        focused(id);
    }

    void on_output (uint id, string output, bool entered) {
        var t = by_id.lookup(id);
        if (t == null) return;
        t.output = entered ? output : (t.output == output ? "" : t.output);
        output_changed(id, t.output);
    }
}
