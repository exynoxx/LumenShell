using LayerShell;
using GLES2;
using Gee;

public class Program {
    public string id;
    public string title;
    public GLuint tex;
}

static Gee.List<Program> entries = null;

public void on_window_new(string app_id, string title){
    print("on_window_new: %s (%s)\n", title, app_id);

    var icon_path = Utils.get_icon_path_from_app_id(app_id);

    print("using icon: %s,\n", icon_path);

    GLuint tex;
    if(icon_path.contains(".svg")){
        var image = DrawKit.image_from_svg(icon_path,32,32);
        tex = DrawKit.texture_upload(*image);
    } else{
        var image = DrawKit.image_load(icon_path);
        tex = DrawKit.texture_upload(image);
    }

    entries.add(new Program(){id=app_id, title=title, tex=tex});
}

public static int main(string[] args) {
    
    int width = 1920;
    int height = 50;

    entries = new ArrayList<Program>();
    LayerShell.register_on_window_new(on_window_new);
    LayerShell.register_on_window_rm((app_id, title) => print("rm: %s (%s)\n", title, app_id));
    LayerShell.register_on_window_focus((app_id, title) => print("focus: %s (%s)\n", title, app_id));
    LayerShell.register_on_mouse_enter(() => {
        print("mouse enter\n");
    });

    LayerShell.init("panel", width, height, BOTTOM, true);
    var mouse_info = LayerShell.seat_mouse_info();
    var ctx = new DrawKit.Context(width, height);
    ctx.set_bg_color(DrawKit.Color(){r=0,g=0,b=0,a=0});

    LayerShell.register_on_mouse_leave(() => {
        print("mouse leave\n");
    });

    while (LayerShell.display_dispatch_blocking() != -1) {
        //if(draw_count <= 0 || entries.size < 1) continue;

        //if(inside) draw_count ++;

        UiLayout.Draw(ctx, mouse_info, entries);
        LayerShell.swap_buffers();

        //draw_count--;
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