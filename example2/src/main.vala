using LayerShell;
using GLES2;

public static int main(string[] args) {
    
    int width = 1920;
    int height = 50;

    LayerShell.init("panel", width, height, BOTTOM, true);
    var mouse_info = LayerShell.seat_mouse_info();
    var ctx = new DrawKit.Context(width, height);
    ctx.set_bg_color(DrawKit.Color(){r=0,g=0,b=0,a=0});

    /*  var path = "/usr/share/icons/hicolor/32x32/apps/fedora-logo-icon.png";
    var image = DrawKit.image_load(path);
    GLuint fedora_tex = DrawKit.texture_upload(image);

    while (LayerShell.display_dispatch_blocking() != -1) {
        UiLayout.Draw(ctx, mouse_info, fedora_tex);
        LayerShell.swap_buffers();
    }  */

    var a = Utils.get_icon_path_from_app_id("org.kde.kontact");
    var b = Utils.get_icon_path_from_app_id("org.kde.dolphin");
    var c = Utils.get_icon_path_from_app_id("org.kde.konsole");
    var d = Utils.get_icon_path_from_app_id("chromium-browser");

    print("%s\n",a);
    print("%s\n",b);
    print("%s\n",c);
    print("%s\n",d);

    return 0;
}


/*  print("Searching for app_id: %s\n", app_id);
    
    string? icon_path = DesktopFileHelper.get_icon_path_from_app_id(app_id, size);
    
    if (icon_path != null) {
        print("✓ Icon found: %s\n", icon_path);
    } else {
        print("✗ Icon not found\n");
    }  */