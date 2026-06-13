using Gtk;
using Gee;

// The whole widget hides itself when there are no items so the trailing
// separator never dangles on its own.
public class SysTray : Gtk.Box {

    Gtk.Box icons;
    SniWatcher watcher;
    HashMap<string, SniItem> by_key = new HashMap<string, SniItem>();

    public SysTray () {
        GLib.Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        add_css_class("systray");
        valign = Gtk.Align.CENTER;

        icons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
        append(icons);

        var sep = new Gtk.Separator(Gtk.Orientation.VERTICAL);
        sep.add_css_class("tray-app-sep");
        append(sep);

        visible = false;   // revealed once the first item registers

        watcher = new SniWatcher();
        watcher.item_added.connect(on_item_added);
        watcher.item_removed.connect(on_item_removed);
        watcher.start();
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
}
