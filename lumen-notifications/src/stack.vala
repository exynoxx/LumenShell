public class BannerStack : Gtk.Box {

    public signal void empty();
    public signal void count_changed(int active_count);
    public signal void close_requested(uint32 id);

    // Active banners only; a leaving banner is already removed.
    private HashTable<uint32, Banner> by_id
        = new HashTable<uint32, Banner>(direct_hash, direct_equal);

    public BannerStack() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: Theme.gap);
        set_halign(Gtk.Align.END);
        set_valign(Gtk.Align.START);
    }

    public Banner add_banner(Notification n) {
        var banner = new Banner(n);
        var rev = new Gtk.Revealer();
        rev.set_transition_type(transition_type());
        rev.set_transition_duration(transition_ms());
        rev.set_child(banner);
        // Reveal before the revealer is mapped so the banner appears at once —
        // GtkRevealer only animates a change made while it is mapped.
        rev.set_reveal_child(true);

        by_id.insert(n.id, banner);
        append(rev);
        count_changed(active_count());
        return banner;
    }

    private static Gtk.RevealerTransitionType transition_type() {
        return Theme.dismiss_style == DismissStyle.FADE
               ? Gtk.RevealerTransitionType.CROSSFADE
               : Gtk.RevealerTransitionType.SLIDE_RIGHT;
    }

    private static uint transition_ms() {
        return Theme.fade_out_ms > 0 ? (uint) Theme.fade_out_ms : 200;
    }

    public Banner? get_banner(uint32 id) {
        return by_id.contains(id) ? by_id.get(id) : null;
    }

    /** Safe to call on an unknown id (no-op). */
    public void dismiss_banner(uint32 id) {
        if (!by_id.contains(id)) return;
        var b = by_id.get(id);
        // Take out of the active map immediately so cascade/dismiss can't
        // double-fire on it.
        by_id.remove(id);
        count_changed(active_count());

        var rev = (Gtk.Revealer) b.get_parent();   // add_banner always wraps
        b.set_sensitive(false);   // no clicks or actions once the leave starts
        rev.notify["child-revealed"].connect(() => {
            if (rev.child_revealed) return;
            remove(rev);
            if (by_id.size() == 0) empty();
        });
        rev.set_reveal_child(false);
    }

    public int active_count() {
        return (int) by_id.size();
    }

    public void cascade_dismiss() {
        uint32[] ids = {};
        Gtk.Widget? child = get_first_child();
        while (child != null) {
            var rev = child as Gtk.Revealer;
            var b = (rev != null) ? ((!) rev).get_child() as Banner : null;
            if (b != null && by_id.contains(((!) b).id)) ids += ((!) b).id;
            child = ((!) child).get_next_sibling();
        }
        if (ids.length == 0) return;

        int step = Theme.cascade_ms > 0 ? Theme.cascade_ms : 60;
        int index = 0;
        close_requested(ids[index++]);
        if (index >= ids.length) return;

        Timeout.add(step, () => {
            close_requested(ids[index++]);
            return (index < ids.length) ? Source.CONTINUE : Source.REMOVE;
        });
    }
}
