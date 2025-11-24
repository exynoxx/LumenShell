using WLUnstable;
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

private void on_window_new(string app_id, string title){
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

private void on_click(Node node){

    if(node == entries[0]){
        print("launching apps");
        return;
    } 

    WLUnstable.toplevel_activate_by_id(node.id, node.title);
}

private void add_launcher_item(){
    var image = DrawKit.image_from_svg("src/res/app.svg",32,32);
    if(image == null){
        print("Launcher icon not found");
        return;
    }
    
    GLuint tex = DrawKit.texture_upload(*image);
    entries.add(new Node(){id="--", title="--", tex=tex, x = 0, y = 0, hovered = false, clicked = false});
}

public static int main(string[] args) {

    int width = 1920;
    int height = 60;
    int underline_height = 5;
    int box_height = height - underline_height;

    entries = new ArrayList<Node>();
    
    WLUnstable.register_on_window_new(on_window_new);
    WLUnstable.register_on_window_rm((app_id, title) => {
        for (var i = 0; i < entries.size ; i++){
            var entry = entries[i];
            if(entry.id == app_id && entry.title == title){
                entries.remove (entry);
                //TODO free
                redraw = true;
            }
        }
    });
    WLUnstable.register_on_window_focus((app_id, title)=>{
        var i = 0;
        foreach(var entry in entries){
            if(entry.id == app_id && entry.title == title){
                active_idx = i;
                redraw = true;
                return;
            }
            i++;
        }
    });

    WLUnstable.register_on_mouse_down(()=>{
        foreach(var box in entries){
            if(box.hovered && !box.clicked){
                box.clicked = true;
                on_click(box);
            }
        }
    });
    WLUnstable.register_on_mouse_up(()=>{
        foreach(var box in entries){
            box.clicked = false;
        }
    });

    WLUnstable.register_on_mouse_motion((x,y) => {
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

    WLUnstable.init("panel", width, height, BOTTOM, true);

    add_launcher_item();

    var ctx = new DrawKit.Context(width, height);
    ctx.set_bg_color(DrawKit.Color(){r=0,g=0,b=0,a=0});

    while (WLUnstable.display_dispatch_blocking() != -1) {
        if(!redraw) continue;

        UiLayout.Draw(ctx, entries, active_idx);
        WLUnstable.swap_buffers();

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