using Gtk;

// Owns one OsdWindow per connected monitor so transient OSD pills appear on
// every display at once. A single persistent `primary` window carries the
// interactive Win+P picker (one keyboard grab); the rest are pill-only mirrors
// pinned to their output. Idempotent reconcile on monitor hotplug.
public class OsdWindowGroup : Object {

    private Gtk.Application app;
    public  OsdWindow       primary;
    private GLib.HashTable<Gdk.Monitor, OsdWindow> mirrors;
    private Gdk.Monitor?    primary_monitor = null;

    public OsdWindowGroup(Gtk.Application app) {
        this.app = app;
        mirrors  = new GLib.HashTable<Gdk.Monitor, OsdWindow>(direct_hash, direct_equal);

        // The persistent primary lives for the whole app — the picker grabs the
        // keyboard on it, so it must never be destroyed across hotplug.
        primary = new OsdWindow(app);
        primary.present();
        primary.set_visible(false);

        var display = (!) Gdk.Display.get_default();
        reconcile();
        display.get_monitors().items_changed.connect((p, r, a) => reconcile());
    }

    // primary + every live mirror.
    public OsdWindow[] windows() {
        var list = new OsdWindow[1 + (int) mirrors.size()];
        list[0] = primary;
        int i = 1;
        mirrors.foreach((mon, win) => { list[i++] = win; });
        return list;
    }

    // Transient pill (volume/brightness/display chip) on every display.
    public void show_pill_view() {
        foreach (var w in windows()) w.show_pill_view();
    }

    public void set_pill_visible(bool visible) {
        foreach (var w in windows()) w.set_visible(visible);
    }

    // The Win+P picker / selector is modal and single-display: keep the mirrors
    // dark so a stale pill on another output can't linger beside it.
    public void hide_mirrors() {
        mirrors.foreach((mon, win) => win.set_visible(false));
    }

    private void reconcile() {
        var display = Gdk.Display.get_default();
        if (display == null) return;

        var model = display.get_monitors();
        uint n = model.get_n_items();

        var live = new GenericArray<Gdk.Monitor>();
        for (uint i = 0; i < n; i++)
            live.add((Gdk.Monitor) model.get_item(i));

        // Drop mirrors whose monitor went away.
        var gone = new GenericArray<Gdk.Monitor>();
        mirrors.foreach((mon, win) => { if (!contains(live, mon)) gone.add(mon); });
        for (int i = 0; i < gone.length; i++) {
            var win = mirrors.get(gone.get(i));
            if (win != null) win.destroy();
            mirrors.remove(gone.get(i));
        }

        if (live.length == 0) return;

        // Keep the persistent primary pinned to a live output.
        if (primary_monitor == null || !contains(live, primary_monitor))
            primary_monitor = live.get(0);
        GtkLayerShell.set_monitor(primary, primary_monitor);

        // The primary's monitor must not also carry a mirror (double pill).
        if (mirrors.contains(primary_monitor)) {
            var dup = mirrors.get(primary_monitor);
            if (dup != null) dup.destroy();
            mirrors.remove(primary_monitor);
        }

        // One pill-only mirror on every non-primary output.
        for (int i = 0; i < live.length; i++) {
            var mon = live.get(i);
            if (mon == primary_monitor) continue;
            if (mirrors.get(mon) == null) make_mirror(mon);
        }
    }

    private void make_mirror(Gdk.Monitor mon) {
        var win = new OsdWindow(app);
        GtkLayerShell.set_monitor(win, mon);
        win.present();
        win.set_visible(false);
        mirrors.set(mon, win);
    }

    private static bool contains(GenericArray<Gdk.Monitor> arr, Gdk.Monitor m) {
        for (int i = 0; i < arr.length; i++)
            if (arr.get(i) == m) return true;
        return false;
    }
}
