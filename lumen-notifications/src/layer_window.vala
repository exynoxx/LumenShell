using Gtk;

public class LayerWindow : Gtk.Window {

    public BannerStack stack;
    public Gtk.Button  clear_btn;
    public signal void clear_all_requested();

    public LayerWindow(Gtk.Application app) {
        Object(application: app);

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-notifications");
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.NONE);
        // Anchor only TOP+RIGHT so the window sizes to natural content height
        // and grows downward as banners stack. Compositor clips at screen
        // bottom for free.
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
        GtkLayerShell.set_margin(this, GtkLayerShell.Edge.TOP,   Theme.margin_top);
        GtkLayerShell.set_margin(this, GtkLayerShell.Edge.RIGHT, Theme.margin_right);

        decorated = false;
        resizable = false;
        add_css_class("lumen-notif-root");

        var outer = new Gtk.Box(Gtk.Orientation.VERTICAL, Theme.gap);
        outer.set_halign(Gtk.Align.END);
        outer.set_valign(Gtk.Align.START);

        clear_btn = new Gtk.Button.with_label("Clear all");
        clear_btn.add_css_class("lumen-notif-clear-all");
        clear_btn.set_size_request(Theme.width, -1);
        clear_btn.set_halign(Gtk.Align.FILL);
        clear_btn.set_visible(false);
        clear_btn.clicked.connect(() => {
            clear_all_requested();
        });
        outer.append(clear_btn);

        stack = new BannerStack();
        stack.count_changed.connect((n) => {
            clear_btn.set_visible(n > Theme.clear_threshold);
        });
        outer.append(stack);

        set_child(outer);
    }
}
