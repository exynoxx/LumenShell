using DrawKit;
using Gee;

public const uint KICKOFF_ID = uint.MAX;

public class Panel {

    public const int HEIGHT = 60;
    public const int UNDERLINE_HEIGHT = 5;
    public const int APP_UNDERLINE_HEIGHT = HEIGHT-UNDERLINE_HEIGHT;

    private int width;
    private HashMap<uint, App> entries;
    private LinkedList<uint> ordering;

    private int active_idx;

    private Context ctx;

    public Panel(int screen_width){
        WLHooks.init_layer_shell("panel", screen_width, HEIGHT, BOTTOM, true);

        ctx = new DrawKit.Context(screen_width, HEIGHT);
        ctx.set_bg_color(DrawKit.Color(){r=0,g=0,b=0,a=0});

        entries = new HashMap<uint, App>();
        entries[KICKOFF_ID] = new App(KICKOFF_ID,"--","--",0);

        ordering = new LinkedList<uint>();
        ordering.add(KICKOFF_ID);
    }

    public void on_window_new(uint id, string app_id, string title){
        var order = entries.size;
        entries[id] = new App(id, app_id, title, order);
        ordering.add(id);
        redraw = true;
    }

    public void on_window_rm(uint window_id){
        if(entries[window_id].order == active_idx) {
            active_idx = 0;
        }

        ordering.remove(window_id);

        entries[window_id].free();
        entries.unset(window_id);

        var i = 0;
        foreach (var id in ordering){
            entries[id].reset_order(i++);
        }

        redraw = true;  
    }

    public void on_window_focus(uint id){
        active_idx = entries[id].order;
        redraw = true;
    }

    public void on_mouse_down(){
        foreach(var app in entries.values){
            if(app.hovered && !app.clicked){
                app.clicked = true;
                app.on_click();
            }
        }
    }

    public void on_mouse_up(){
        foreach(var app in entries.values){
            app.clicked = false;
        }
    }
    
    public void on_mouse_motion(int x, int y){
        foreach(var app in entries.values){
            app.mouse_motion(x,y);
        }
    }

    public void on_mouse_leave(){
        foreach(var app in entries.values){
            app.hovered = false;
        }
        redraw = true;
    }

    public void render(){
        ctx.begin_frame();

        //sep
        ctx.draw_rect(App.WIDTH, 10, 2, App.HEIGHT-20, Color(){r=0,g=0,b=0,a=1});

        //launcher + open programs
        foreach(var app in entries.values)
            app.render(ctx);

        //underline
        float shade = 0.15f;
        ctx.draw_rect(0, App.HEIGHT, App.WIDTH, APP_UNDERLINE_HEIGHT, Color(){r=shade,g=shade,b=shade,a=1});

        //active
        if(active_idx > 0){
            var color = Color(){r=0,g=0.17f,b=0.9f,a=1};
            ctx.draw_rect(active_idx*App.WIDTH+2, App.HEIGHT, App.WIDTH, APP_UNDERLINE_HEIGHT, color);
        }

        ctx.end_frame();
    }
}