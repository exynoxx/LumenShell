public class PageDots : Gtk.Box {

    private Gtk.Label[] dots;
    private int active = 0;

    public PageDots(int page_count) {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 10);
        add_css_class("page-dots");
        set_halign(Gtk.Align.CENTER);

        dots = new Gtk.Label[page_count];
        for (int i = 0; i < page_count; i++) {
            var dot = new Gtk.Label((i + 1).to_string());
            dot.add_css_class("page-dot");
            dots[i] = dot;
            append(dot);
        }
        if (page_count > 0) dots[0].add_css_class("active");
    }

    public void set_active(int page) {
        if (page < 0 || page >= dots.length) return;
        if (active < dots.length) dots[active].remove_css_class("active");
        dots[page].add_css_class("active");
        active = page;
    }
}
