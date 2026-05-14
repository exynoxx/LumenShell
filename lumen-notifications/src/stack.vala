using Gtk;

/**
 * Vertical column of banner widgets.
 *
 *   - `by_id` maps id → Banner only for *active* (not-yet-leaving) banners.
 *     A banner whose leave animation is running has already been removed
 *     from this map so it does not get included in `cascade_dismiss` or
 *     trigger another close.
 *
 *   - Removal flow: `dismiss_banner(id)` starts the leave animation; on
 *     `leave_finished` the widget is removed from the box and `empty()` /
 *     `count_changed()` fire as needed.
 */
public class BannerStack : Gtk.Box {

    public signal void empty();
    public signal void count_changed(int active_count);
    /** Fired when the user requests close-via-cascade for a specific id. */
    public signal void close_requested(uint32 id);

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
        count_changed(active_count());
        return banner;
    }

    public Banner? get_banner(uint32 id) {
        return by_id.contains(id) ? by_id.get(id) : null;
    }

    /**
     * Begin the leave animation for `id` and remove the widget after it
     * finishes. Safe to call on an unknown id (no-op).
     */
    public void dismiss_banner(uint32 id) {
        if (!by_id.contains(id)) return;
        var b = by_id.get(id);
        // Take out of the active map immediately so cascade/dismiss can't
        // double-fire on it.
        by_id.remove(id);
        count_changed(active_count());

        b.leave_finished.connect(() => {
            remove(b);
            if (by_id.size() == 0) empty();
        });
        b.begin_leave(Theme.dismiss_style);
    }

    public int active_count() {
        return (int) by_id.size();
    }

    /**
     * Walk all currently-active banners in visual (top→bottom) order and
     * fire `close_requested(id)` for each, staggered by `Theme.cascade_ms`.
     */
    public void cascade_dismiss() {
        uint32[] ids = {};
        Gtk.Widget? child = get_first_child();
        while (child != null) {
            if (child is Banner) {
                var b = (Banner) (!) child;
                if (by_id.contains(b.id)) ids += b.id;
            }
            child = ((!) child).get_next_sibling();
        }

        uint delay = 0;
        foreach (uint32 id in ids) {
            uint32 capture = id;
            uint d = delay;
            Timeout.add(d, () => {
                close_requested(capture);
                return Source.REMOVE;
            });
            int step = Theme.cascade_ms > 0 ? Theme.cascade_ms : 60;
            delay += step;
        }
    }
}
