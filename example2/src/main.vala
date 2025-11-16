using LayerShell;
using GLES2;

public class Program {
    public string id;
    public string title;
    public GLuint tex;
}

static List<Program> entries = null;

public static int main(string[] args) {
    
    int width = 1920;
    int height = 50;

    entries = new List<Program>();
    
    LayerShell.register_on_window_new((app_id, title) => {
        print("callback enter\n");
        print("New: %s (%s)\n", title, app_id);
        var icon_path = Utils.get_icon_path_from_app_id(app_id);
        print("path: %s\n", icon_path);
        var image = DrawKit.image_from_svg(icon_path,32,32);
        print("image\n");
        GLuint fedora_tex = DrawKit.texture_upload(*image);
        print("tex\n");
        entries.append(new Program(){id=app_id, title=title, tex=fedora_tex});
    });
    LayerShell.register_on_window_rm((app_id, title) => print("rm: %s (%s)\n", title, app_id));

    LayerShell.init("panel", width, height, BOTTOM, true);
    var mouse_info = LayerShell.seat_mouse_info();
    var ctx = new DrawKit.Context(width, height);
    ctx.set_bg_color(DrawKit.Color(){r=0,g=0,b=0,a=0});
/*  
    var a = Utils.get_icon_path_from_app_id("org.kde.kontact");
    var b = Utils.get_icon_path_from_app_id("org.kde.dolphin");
    var c = Utils.get_icon_path_from_app_id("org.kde.konsole");
    var d = Utils.get_icon_path_from_app_id("chromium-browser");  */

    /*  print("%s\n",a);
    print("%s\n",b);
    print("%s\n",c);
    print("%s\n",d);  */

    while (LayerShell.display_dispatch_blocking() != -1) {
        UiLayout.Draw(ctx, mouse_info, entries);
        LayerShell.swap_buffers();
    }

    return 0;
}


/*  print("Searching for app_id: %s\n", app_id);
    
    string? icon_path = DesktopFileHelper.get_icon_path_from_app_id(app_id, size);
    
    if (icon_path != null) {
        print("✓ Icon found: %s\n", icon_path);
    } else {
        print("✗ Icon not found\n");
    }  */