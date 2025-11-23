using Gtk;
using Gdk;
using GtkLayerShell;

public struct Program {
    public string app_id;
    public string title;
    public Gdk.Texture tex;
}

public class LayerShellBar : Gtk.ApplicationWindow {
    private DrawingArea drawing_area;
    
    public LayerShellBar(Gtk.Application app) {
        Object(application: app);
        
        // Initialize layer shell
        GtkLayerShell.init_for_window(this);
        
        // Configure layer shell
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_namespace(this, "custom-bar");
        
        // Anchor to top edge
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, false);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
        
        // Set exclusive zone
        GtkLayerShell.set_exclusive_zone(this, 32);

        // In your window class or after window is realized
       /*   var gdk_display = this.get_display(); // or Gdk.Display.get_default()
    
        // You need to use the Wayland-specific functions
        // This requires gdk-wayland bindings
        #if GDK_WINDOWING_WAYLAND
        var wl_display = Gdk.Wayland.Display.get_wl_display(gdk_display);
        #endif  */

        //print("wl_display %A", wl_display);

        // Create custom bar

        string css = """
            window {
                background-color: transparent;
            }
            """;

        var provider = new Gtk.CssProvider ();
        provider.load_from_data ((uint8[]) css);
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        drawing_area = new DrawingArea();
        set_child(drawing_area);
    }
}

public class Application : Gtk.Application {
    public Application() {
        Object(application_id: "com.example.layershellbar", flags: ApplicationFlags.FLAGS_NONE);
    }
    
    protected override void activate() {
        var window = new LayerShellBar(this);
        window.present();
        window.realize();

        var gdk_display = window.get_display();
        if (gdk_display == null) {
            print("gdk_display null\n");
            return;
        }

        var toplevel_mngr = new TopLevelManager();
        toplevel_mngr.init(gdk_display);
    }


    public static int main(string[] args) {

        Environment.set_variable("GDK_BACKEND", "wayland", true);
        
        var app = new Application();
        return app.run(args);
    }
}

