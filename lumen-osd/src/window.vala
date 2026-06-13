using Gtk;

public class OsdWindow : Gtk.Window {

    public Pill     pill;
    public Selector selector;

    public OsdWindow(Gtk.Application app) {
        Object(application: app);

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-osd");
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.NONE);
        apply_position();

        decorated = false;
        resizable = false;
        add_css_class("lumen-osd-root");

        pill = new Pill();
        pill.set_halign(Gtk.Align.CENTER);
        pill.set_valign(Gtk.Align.CENTER);

        selector = new Selector();
        selector.set_halign(Gtk.Align.CENTER);
        selector.set_valign(Gtk.Align.CENTER);

        set_child(pill);
    }

    // Transient pill (volume/brightness/display chip): the themed edge anchor.
    public void show_pill_view() {
        apply_position();
        if (get_child() != pill) set_child(pill);
    }

    // Win+P selector: drawn dead-center, regardless of the themed pill anchor.
    public void show_selector_view() {
        center_position();
        if (get_child() != selector) set_child(selector);
    }

    // Win+P picker: take an exclusive keyboard grab so we see every key
    // (including the Super release that commits the choice). Released back to
    // NONE the moment the pick ends, so the OSD never steals keys otherwise.
    public void grab_keyboard() {
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.EXCLUSIVE);
    }

    public void release_keyboard() {
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.NONE);
    }

    // Unanchored on every edge ⇒ gtk4-layer-shell centers the surface.
    private void center_position() {
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP,    false);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, false);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT,   false);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT,  false);
    }

    private void apply_position() {
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP,    false);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, false);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT,   false);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT,  false);

        switch (Theme.position) {
            case "top-center":
                GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
                GtkLayerShell.set_margin(this, GtkLayerShell.Edge.TOP, Theme.margin);
                break;
            case "bottom-right":
                GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
                GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT,  true);
                GtkLayerShell.set_margin(this, GtkLayerShell.Edge.BOTTOM, Theme.margin);
                GtkLayerShell.set_margin(this, GtkLayerShell.Edge.RIGHT,  Theme.margin);
                break;
            case "bottom-left":
                GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
                GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT,   true);
                GtkLayerShell.set_margin(this, GtkLayerShell.Edge.BOTTOM, Theme.margin);
                GtkLayerShell.set_margin(this, GtkLayerShell.Edge.LEFT,   Theme.margin);
                break;
            case "bottom-center":
            default:
                GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
                GtkLayerShell.set_margin(this, GtkLayerShell.Edge.BOTTOM, Theme.margin);
                break;
        }
    }
}
