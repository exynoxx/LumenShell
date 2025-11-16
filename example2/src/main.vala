using LayerShell;
using GLES2;
using Gee;

public class Program {
    public string id;
    public string title;
    public GLuint tex;
}

static Gee.List<Program> entries = null;

public static GLuint Upload_svg(string path){
    print("uploading texture: %s\n", path);
    var image = DrawKit.image_from_svg(path,32,32);
    print("image\n");
    GLuint tex = DrawKit.texture_upload(*image);
    //free(image);
    print("done\n");
    return tex;
}

public static int main(string[] args) {
    
    int width = 1920;
    int height = 50;

    entries = new ArrayList<Program>();
    LayerShell.register_on_window_new((app_id, title) => {
        print("register_on_window_new: %s (%s)\n", title, app_id);
        var icon_path = Utils.get_icon_path_from_app_id(app_id);
        var tex = Upload_svg(icon_path);
        entries.add(new Program(){id=app_id, title=title, tex=tex});
    });
    LayerShell.register_on_window_rm((app_id, title) => print("rm: %s (%s)\n", title, app_id));

    LayerShell.init("panel", width, height, BOTTOM, true);
    var mouse_info = LayerShell.seat_mouse_info();
    mouse_info.pointer_inside = true;
    var ctx = new DrawKit.Context(width, height);
    ctx.set_bg_color(DrawKit.Color(){r=0,g=0,b=0,a=0});


    while (LayerShell.display_dispatch_blocking() != -1) {

        if(!mouse_info.pointer_inside) continue;
        if(entries.size < 1) continue;

        UiLayout.Draw(ctx, mouse_info, entries);
        LayerShell.swap_buffers();
    }

    return 0;
}


/*  
var a = Utils.get_icon_path_from_app_id("org.kde.kontact");
var b = Utils.get_icon_path_from_app_id("org.kde.dolphin");
var c = Utils.get_icon_path_from_app_id("org.kde.konsole");
var d = Utils.get_icon_path_from_app_id("chromium-browser");

print("%s\n",a);
print("%s\n",b);
print("%s\n",c);
print("%s\n",d);
  */