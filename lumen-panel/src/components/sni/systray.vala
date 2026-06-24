using Gtk;
using Gee;

// The whole widget hides itself when there are no items so the trailing
// separator never dangles on its own.
public class SysTray : Gtk.Box, ITrayApplet {

    Gtk.Box icons;
    SniWatcher watcher;
    HashMap<string, SniItem> by_key = new HashMap<string, SniItem>();

    // The watcher (the singleton D-Bus name owner + item registry) is shared:
    // one instance, owned by App, drives every SysTray widget. Each monitor's
    // SysTray builds its own SniItem widgets from the same item set — a GTK
    // widget can live in only one window, so the icons can't be shared, but the
    // underlying registration is.
    public SysTray (SniWatcher watcher) {
        GLib.Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        add_css_class("systray");
        valign = Gtk.Align.CENTER;

        icons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
        append(icons);

        var sep = new Gtk.Separator(Gtk.Orientation.VERTICAL);
        sep.add_css_class("tray-app-sep");
        append(sep);

        visible = false;   // revealed once the first item registers

        this.watcher = watcher;
        watcher.item_added.connect(on_item_added);
        watcher.item_removed.connect(on_item_removed);
        // Replay items that registered before this widget attached (secondary
        // monitors / post-hotplug rebuilds).
        watcher.foreach_item(on_item_added);
    }

    void on_item_added (string bus, string path, string key) {
        if (by_key.has_key(key)) return;
        var item = new SniItem(bus, path, key);
        by_key[key] = item;
        icons.append(item);
        update_visibility();
    }

    void on_item_removed (string key) {
        if (!by_key.has_key(key)) return;
        var item = by_key[key];
        icons.remove(item);
        by_key.unset(key);
        update_visibility();
    }

    void update_visibility () {
        visible = by_key.size > 0;
    }

    // Icon-only applet: the systray box IS its own tray widget (its trailing
    // separator stays inside), no control module.
    public Gtk.Widget  tray_widget () { return this; }
}
