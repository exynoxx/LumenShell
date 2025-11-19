using Gtk;
using Gdk;
using GtkLayerShell;

public class CustomBar : Gtk.DrawingArea {
    private string time_text;
    private string sample_text = "GTK Layer Shell Bar";
    
    public CustomBar() {
        set_content_width(1920);
        set_content_height(32);
        
        time_text = get_time();
        
        // Update time every second
        Timeout.add_seconds(1, () => {
            time_text = get_time();
            queue_draw();
            return true;
        });
    }
    
    private string get_time() {
        var now = new DateTime.now_local();
        return now.format("%H:%M:%S");
    }
    
    // Override snapshot method instead of using set_draw_func
    public override void snapshot(Gtk.Snapshot snapshot) {
        int width = get_width();
        int height = get_height();
        
        // Background
        var bg_rect = Graphene.Rect() {
            origin = { 0, 0 },
            size = { width, height }
        };
        var bg_color = RGBA();
        bg_color.parse("#1e1e2e");
        snapshot.append_color(bg_color, bg_rect);
        
        // Left section - sample text
        draw_text(snapshot, sample_text, 10, height / 2.0f, "#cdd6f4");
        
        // Right section - time
        float time_width = time_text.length * 9.0f;
        draw_text(snapshot, time_text, width - time_width - 10, height / 2.0f, "#f38ba8");
        
        // Center indicator line
        var line_rect = Graphene.Rect() {
            origin = { width / 2.0f - 1, 8 },
            size = { 2, height - 16 }
        };
        var line_color = RGBA();
        line_color.parse("#89b4fa");
        line_color.alpha = 0.3f;
        snapshot.append_color(line_color, line_rect);
        
        // Left accent box
        var box_rect = Graphene.Rect() {
            origin = { 5, height / 2.0f - 8 },
            size = { 3, 16 }
        };
        var box_color = RGBA();
        box_color.parse("#a6e3a1");
        snapshot.append_color(box_color, box_rect);
    }
    
    private void draw_text(Gtk.Snapshot snapshot, string text, float x, float y, string color_str) {
        var color = RGBA();
        color.parse(color_str);
        
        // Create Pango layout
        var layout = create_pango_layout(text);
        
        // Get text dimensions
        int text_width, text_height;
        layout.get_pixel_size(out text_width, out text_height);
        
        // Position and draw
        snapshot.save();
        var point = Graphene.Point() {
            x = x,
            y = y - text_height / 2.0f
        };
        snapshot.translate(point);
        snapshot.append_layout(layout, color);
        snapshot.restore();
    }
}

public class LayerShellBar : Gtk.ApplicationWindow {
    private CustomBar bar;
    
    public LayerShellBar(Gtk.Application app) {
        Object(application: app);
        
        // Initialize layer shell
        GtkLayerShell.init_for_window(this);
        
        // Configure layer shell
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_namespace(this, "custom-bar");
        
        // Anchor to top edge
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, false);
        
        // Set exclusive zone
        GtkLayerShell.set_exclusive_zone(this, 32);
        
        // Create custom bar
        bar = new CustomBar();
        set_child(bar);
    }
}

public class BarApplication : Gtk.Application {
    public BarApplication() {
        Object(application_id: "com.example.layershellbar", flags: ApplicationFlags.FLAGS_NONE);
    }
    
    protected override void activate() {
        var window = new LayerShellBar(this);
        window.present();
    }
}

public static int main(string[] args) {
    var app = new BarApplication();


    // In your window class or after window is realized
    var gdk_display = this.get_display(); // or Gdk.Display.get_default()

    // You need to use the Wayland-specific functions
    // This requires gdk-wayland bindings
    #if GDK_WINDOWING_WAYLAND
    var wl_display = Gdk.Wayland.Display.get_wl_display(gdk_display);
    #endif

    return app.run(args);
}