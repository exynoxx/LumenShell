using Gtk;

/**
 * Vertical column of banner widgets. Owns the mapping from notification id
 * to banner widget so the manager's add/update/close signals can be wired
 * straight through. Hides the parent layer-shell window when empty.
 */
public class BannerStack : Gtk.Box {

    public signal void empty();

    private HashTable<uint32, Banner> by_id
        = new HashTable<uint32, Banner>(direct_hash, direct_equal);

    public BannerStack() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: Theme.gap);
        set_halign(Gtk.Align.END);
        set_valign(Gtk.Align.START);
    }

    public Banner add_banner(Notification n) {
        var banner = new Banner(n);
        by_id.insert(n.id, banner);
        append(banner);
        return banner;
    }

    public Banner? get_banner(uint32 id) {
        return by_id.contains(id) ? by_id.get(id) : null;
    }

    public void remove_banner(uint32 id) {
        if (!by_id.contains(id)) return;
        var b = by_id.get(id);
        by_id.remove(id);
        remove(b);
        if (by_id.size() == 0) empty();
    }

    public int count() {
        return (int) by_id.size();
    }
}
