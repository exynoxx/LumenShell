using Gtk;

public class LayerWindow : Gtk.Window {

    public BannerStack stack;

    public LayerWindow(Gtk.Application app) {
        Object(application: app);

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-notifications");
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.NONE);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
        GtkLayerShell.set_margin(this, GtkLayerShell.Edge.TOP,   Theme.margin_top);
        GtkLayerShell.set_margin(this, GtkLayerShell.Edge.RIGHT, Theme.margin_right);
        // No exclusive zone — notifications never claim screen real estate.

        decorated = false;
        resizable = false;
        add_css_class("lumen-notif-root");

        stack = new BannerStack();
        set_child(stack);
    }
}
