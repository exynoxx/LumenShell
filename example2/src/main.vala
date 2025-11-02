using LayerShell;
using DrawKit;
using DrawKit.Texture;

public class Panel {
    public static int main(string[] args) {
        int width = 1920;  // typical screen width, adjust as needed
        int height = 50;

        LayerShell.init("panel", width, height, Edge.BOTTOM);
        EGL.Display egl_display = LayerShell.get_egl_display();
        EGL.Surface egl_surface = LayerShell.get_egl_surface();
        unowned Wl.Display display = LayerShell.get_wl_display();

        DrawKit.Context ctx = DrawKit.Context();
        DrawKit.init(ref ctx, width, height);
        DrawKit.set_bg_color(ref ctx, 0.0f, 0.0f, 0.0f, 0.0f);

        unowned var mouse_info = LayerShell.mouse_info();

        string fedora = "/usr/share/icons/hicolor/32x32/apps/fedora-logo-icon.png";

        var img = DrawKit.Texture.load_icon(fedora);
        var icon_tex = DrawKit.Texture.upload(img);
        
        // --- Render loop ---
        while (display.dispatch() != -1) {
            print("Mouse: %f, %f\n", mouse_info.mouse_x, mouse_info.mouse_y);

            DrawKit.begin_frame(ref ctx);
            
            DrawKit.set_color(ref ctx, 1.0f, 1.0f, 1.0f, 0.1f);
            DrawKit.draw_rect(ref ctx, 0, 0, 50, height);

            DrawKit.set_color(ref ctx, 1.0f, 1.0f, 1.0f, 1.0f);
            DrawKit.draw_texture(ref ctx, icon_tex, 10, 9, 32, 32);
            DrawKit.draw_texture(ref ctx, icon_tex, 60, 9, 32, 32);
            DrawKit.draw_texture(ref ctx, icon_tex, 110, 9, 32, 32);

            DrawKit.end_frame();
            EGL.swap_buffers(egl_display, egl_surface);
        }

        // --- Cleanup ---
        LayerShell.destroy();
        return 0;
    }
}