using DrawKit;
using Gee;

public const int HEIGHT = 300;
public const int EXCLUSIVE_HEIGHT = 60;
public const int UNDERLINE_HEIGHT = 5;

public const int APP_UNDERLINE_Y = HEIGHT-UNDERLINE_HEIGHT;
public const int APP_Y = HEIGHT-EXCLUSIVE_HEIGHT;
public const int APP_WIDTH = 70;
public const int APP_HEIGHT = EXCLUSIVE_HEIGHT;


public class Panel {

    private int width;
    private HashMap<uint, App> entries;
    private LinkedList<uint> ordering;

    private int active_idx;

    private Context ctx;
    private Tray tray;

    public Panel(int screen_width){
        WLHooks.init_layer_shell("panel", screen_width, HEIGHT, BOTTOM, true, EXCLUSIVE_HEIGHT);

        ctx = new DrawKit.Context(screen_width, HEIGHT);
        ctx.set_bg_color(DrawKit.Color(){r=0,g=0,b=0,a=0});

        entries = new HashMap<uint, App>();
        entries[KICKOFF_ID] = new App(KICKOFF_ID,"--","--",0);

        ordering = new LinkedList<uint>();
        ordering.add(KICKOFF_ID);

        tray = new Tray(ctx, screen_width);
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
        tray.on_mouse_down();
    }

    public void on_mouse_up(){
        foreach(var app in entries.values){
            app.clicked = false;
        }
        tray.on_mouse_up();
    }
    
    public void on_mouse_motion(int x, int y){
        foreach(var app in entries.values){
            app.mouse_motion(x,y);
        }
        tray.on_mouse_motion(x,y);
    }

    public void on_mouse_leave(){
        foreach(var app in entries.values){
            app.hovered = false;
        }
        redraw = true;
        tray.on_mouse_leave();
    }

    public void render(){
        ctx.begin_frame();

        //sep
        //ctx.draw_rect(App.WIDTH, 10, 2, App.HEIGHT-20, Color(){r=0,g=0,b=0,a=1});

        //launcher + open programs
        foreach(var app in entries.values)
            app.render(ctx);

        //active
        if(active_idx > 0){
            var color = Color(){r=0,g=0.17f,b=0.9f,a=1};
            ctx.draw_rect(active_idx*APP_WIDTH+2, APP_UNDERLINE_Y, APP_WIDTH, UNDERLINE_HEIGHT, color);
        }

        tray.render();

        ctx.end_frame();
    }
}