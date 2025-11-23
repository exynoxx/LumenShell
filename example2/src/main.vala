using LayerShell;
using GLES2;
using Gee;

public class Node {
    public string id;
    public string title;
    public GLuint tex;
    public bool hovered;
    public bool clicked;
    public int x;
    public int y;
}

int box_width = 70;

static Gee.List<Node> entries = null;
static int active_idx = -1;
static bool redraw = true;

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

    entries.add(new Node(){id=app_id, title=title, tex=tex, x = entries.size * box_width, y = 0, hovered = false, clicked = false});
    redraw = true;
}

public static void on_window_focus(string app_id, string title){
    for(int i = 0; i < entries.size; i++){
        if(entries[i].id == app_id && entries[i].title == title){
            active_idx = i;
            redraw = true;
            return;
        }
    }
}

public static int main(string[] args) {

    int width = 1920;
    int height = 60;
    int underline_height = 5;
    int box_height = height - underline_height;

    entries = new ArrayList<Node>();
    LayerShell.register_on_window_new(on_window_new);
    LayerShell.register_on_window_rm((app_id, title) => print("rm: %s (%s)\n", title, app_id));
    LayerShell.register_on_window_focus(on_window_focus);

    LayerShell.register_on_mouse_down(()=>{
        print("mouse_down\n");
        foreach(var box in entries){
            if(box.hovered && !box.clicked){
                box.clicked = true;
                print("clicked activate %s\n", box.title);
                LayerShell.toplevel_activate_by_id(box.id, box.title);
            }
        }
    });
    LayerShell.register_on_mouse_up(()=>{
        print("mouse_up\n");
        foreach(var box in entries){
            box.clicked = false;
        }
    });

    LayerShell.register_on_mouse_motion((x,y) => {
        foreach(var box in entries){
            var box_x = box.x;
            var box_y = box.y;
            var oldval = box.hovered;
            box.hovered = (
                x >= box_x && 
                x <= box_x + box_width &&
                y >= box_y && 
                y <= box_y + box_height);

            if(box.hovered != oldval) redraw = true;
            box_x += box_width;
        }
    });

    LayerShell.init("panel", width, height, BOTTOM, true);

    var ctx = new DrawKit.Context(width, height);
    ctx.set_bg_color(DrawKit.Color(){r=0,g=0,b=0,a=0});

    while (LayerShell.display_dispatch_blocking() != -1) {
        //if(draw_count <= 0 || entries.size < 1) continue;

        if(!redraw) continue;

        UiLayout.Draw(ctx, entries, active_idx);
        LayerShell.swap_buffers();

        redraw = false;
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