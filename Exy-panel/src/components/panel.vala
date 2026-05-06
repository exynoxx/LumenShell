using DrawKit;
using Gee;

public const int HEIGHT = 300;
public const int EXCLUSIVE_HEIGHT = 60;
public const int UNDERLINE_HEIGHT = 5;

public const int APP_UNDERLINE_Y = HEIGHT-UNDERLINE_HEIGHT;
public const int APP_Y = HEIGHT-EXCLUSIVE_HEIGHT;
public const int APP_WIDTH = 70;
public const int APP_HEIGHT = EXCLUSIVE_HEIGHT;
public const uint32 BTN_LEFT = 272;
public const uint32 BTN_RIGHT = 273;

public const int POPUP_ANIM_ID = 200;
public const int POPUP_W = 220;
public const int POPUP_H = 86;
public const int POPUP_GAP = 8;
public const int POPUP_TITLE_H = 42;

public class Panel {

    private ArrayList<App> entries;
    private HashMap<string, App> app_index;
    private HashMap<uint, App> window_index;

    private uint active_window_id;
    private int screen_width;

    private Context ctx;
    private Tray tray;

    private string pins_file;

    private int last_mouse_x = -1;
    private int last_mouse_y = -1;

    private App? popup_app = null;
    private int popup_x = 0;
    private int popup_y = 0;
    private int popup_h = 0;
    private bool popup_action_hovered = false;
    private bool popup_action_pressed = false;

    public Panel(){
        var size = WLHooks.get_screen_size();
        screen_width = size.width;

        WLHooks.init_layer_shell("panel", screen_width, HEIGHT, BOTTOM, true, EXCLUSIVE_HEIGHT);

        ctx = new DrawKit.Context(screen_width, HEIGHT);
        ctx.set_bg_color(DrawKit.Color(){r=0,g=0,b=0,a=0});

        entries = new ArrayList<App>();
        app_index = new HashMap<string, App>();
        window_index = new HashMap<uint, App>();

        var kickoff = new App("--", "Launcher", "", 0, true);
        entries.add(kickoff);

        tray = new Tray(ctx, screen_width);

        pins_file = Path.build_filename(Environment.get_user_config_dir(), "exy-panel", "pinned-apps.txt");
        load_pins();
        relayout();
        update_input_region();
    }

            public void on_window_new(uint id, string app_id, string title){
                var item = get_or_create_app(app_id, title);
                item.add_window(id);
                window_index[id] = item;
                if(item.title == app_id || item.title == "") {
                    item.title = title;
                }
                relayout();
                redraw = true;
            }

            public void on_window_rm(uint window_id){
                if(!window_index.has_key(window_id)) {
                    return;
                }

                var item = window_index[window_id];
                item.remove_window(window_id);
                window_index.unset(window_id);

                if(active_window_id == window_id) {
                    active_window_id = 0;
                }

                if(!item.is_launcher && !item.is_pinned && !item.has_open_windows()){
                    if(popup_app == item) hide_popup();
                    remove_app(item);
                }

                relayout();
                redraw = true;
            }

            public void on_window_focus(uint id){
                if(!window_index.has_key(id)) return;
                active_window_id = id;
                window_index[id].on_window_focused(id);
                redraw = true;
            }

            public void on_mouse_down(uint32 button){
                if(button == BTN_RIGHT){
                    var hovered = get_hovered_app();
                    if(hovered != null && !hovered.is_launcher){
                        show_popup_for(hovered);
                        hovered.clicked = true;
                        redraw = true;
                        return;
                    }

                    hide_popup();
                    return;
                }

                if(button != BTN_LEFT) {
                    return;
                }

                if(is_popup_open()){
                    if(point_in_popup_action(last_mouse_x, last_mouse_y)){
                        popup_action_pressed = true;
                        redraw = true;
                        return;
                    }

                    popup_action_pressed = false;

                    if(point_in_popup(last_mouse_x, last_mouse_y)){
                        redraw = true;
                        return;
                    }

                    hide_popup();
                }

                foreach(var app in entries){
                    if(app.hovered && !app.clicked){
                        app.clicked = true;
                        app.on_click();
                        redraw = true;
                        return;
                    }
                }

                tray.on_mouse_down();
            }

            public void on_mouse_up(uint32 button){
                if(button != BTN_LEFT && button != BTN_RIGHT) return;

                if(button == BTN_LEFT && is_popup_open()){
                    var was_pressed = popup_action_pressed;
                    popup_action_pressed = false;

                    if(was_pressed && point_in_popup_action(last_mouse_x, last_mouse_y)){
                        if(click_popup_action(last_mouse_x, last_mouse_y)){
                            hide_popup();
                            redraw = true;
                            return;
                        }
                    }
                }

                foreach(var app in entries){
                    app.clicked = false;
                }
                if(button == BTN_LEFT){
                    tray.on_mouse_up();
                }
            }

            public void on_mouse_motion(int x, int y){
                last_mouse_x = x;
                last_mouse_y = y;

                var old_popup_hover = popup_action_hovered;
                popup_action_hovered = point_in_popup_action(x, y);
                if(old_popup_hover != popup_action_hovered){
                    redraw = true;
                }

                foreach(var app in entries){
                    app.mouse_motion(x,y);
                }
                tray.on_mouse_motion(x,y);

                update_input_region();
            }

            public void on_mouse_leave(){
                foreach(var app in entries){
                    app.hovered = false;
                }
                hide_popup();
                update_input_region();
                redraw = true;
                tray.on_mouse_leave();
            }

            public void on_mouse_scroll(int amount){
                tray.on_mouse_scroll(amount);
            }

            public void render(){
                ctx.begin_frame();

                foreach(var app in entries)
                    app.render(ctx);

                if(active_window_id > 0 && window_index.has_key(active_window_id)){
                    var active = window_index[active_window_id];
                    var color = Color(){r=0,g=0.17f,b=0.9f,a=1};
                    ctx.draw_rect(active.x, APP_UNDERLINE_Y, APP_WIDTH, UNDERLINE_HEIGHT, color);
                }

                render_popup();

                tray.render();

                update_input_region();

                DrawKit.Context.end_frame();
            }

            private App? get_hovered_app(){
                foreach (var app in entries) {
                    if(app.hovered) return app;
                }
                return null;
            }

            private App get_or_create_app(string app_id, string fallback_title){
                if(app_index.has_key(app_id)) return app_index[app_id];

                var name = Utils.get_display_name_from_app_id(app_id);
                if(name == app_id && fallback_title != "") name = fallback_title;

                var launch = Utils.get_launch_cmd_from_app_id(app_id);
                var item = new App(app_id, name, launch, entries.size, false);

                entries.add(item);
                app_index[app_id] = item;
                relayout();
                return item;
            }

            private void remove_app(App item){
                entries.remove(item);
                app_index.unset(item.app_id);
                item.free();
                relayout();
            }

            private void relayout(){
                for(int i = 0; i < entries.size; i++){
                    entries[i].reset_order(i);
                }
            }

            private void load_pins(){
                var pins = Ini.read_lines(pins_file);
                foreach (var app_id in pins) {
                    if(app_id == "" || app_id == "--") continue;
                    if(app_index.has_key(app_id)) continue;

                    var name = Utils.get_display_name_from_app_id(app_id);
                    var launch = Utils.get_launch_cmd_from_app_id(app_id);
                    var app = new App(app_id, name, launch, entries.size, false);
                    app.set_pinned(true);
                    entries.add(app);
                    app_index[app_id] = app;
                }
            }

            private void save_pins(){
                var pins = new ArrayList<string>();
                foreach (var app in entries) {
                    if(app.is_pinned && !app.is_launcher) {
                        pins.add(app.app_id);
                    }
                }
                Ini.write_lines(pins_file, pins);
            }

            private void show_popup_for(App app){
                popup_app = app;

                var target_x = app.x + (APP_WIDTH - POPUP_W) / 2;
                if(target_x < 4) target_x = 4;
                if(target_x + POPUP_W > screen_width - 4) {
                    target_x = screen_width - POPUP_W - 4;
                }

                popup_x = target_x;
                popup_h = 0;
                popup_action_hovered = false;
                popup_action_pressed = false;
                animations.add(new Transition1D(POPUP_ANIM_ID, &popup_h, POPUP_H, 0.18d));
                update_popup_y();
                update_input_region();
            }

            private void hide_popup(){
                if(!is_popup_open()) return;
                popup_app = null;
                popup_h = 0;
                popup_action_hovered = false;
                popup_action_pressed = false;
                update_input_region();
            }

            private bool is_popup_open(){
                return popup_app != null;
            }

            private void update_popup_y(){
                popup_y = APP_Y - popup_h - POPUP_GAP;
            }

            private bool point_in_popup(int x, int y){
                if(!is_popup_open()) return false;
                update_popup_y();
                return x >= popup_x && x <= popup_x + POPUP_W && y >= popup_y && y <= popup_y + popup_h;
            }

            private bool point_in_popup_action(int x, int y){
                if(!point_in_popup(x, y)) return false;
                return y >= popup_y + POPUP_TITLE_H;
            }

            private bool click_popup_action(int x, int y){
                if(!is_popup_open() || popup_app == null) return false;
                if(!point_in_popup_action(x, y)) return false;

                popup_app.set_pinned(!popup_app.is_pinned);
                save_pins();

                if(!popup_app.is_pinned && !popup_app.has_open_windows()){
                    remove_app(popup_app);
                }

                relayout();
                redraw = true;
                return true;
            }

            private void render_popup(){
                if(!is_popup_open() || popup_app == null || popup_h <= 0) return;

                update_popup_y();

                var bg = Color(){r=0.08f,g=0.09f,b=0.14f,a=0.98f};
                var border = Color(){r=0.2f,g=0.24f,b=0.38f,a=1f};
                var sep = Color(){r=0.2f,g=0.24f,b=0.38f,a=0.8f};
                var text = Color(){r=0.92f,g=0.93f,b=0.98f,a=1f};
                var action = Color(){r=0.74f,g=0.80f,b=1f,a=1f};
                var action_bg = Color(){r=0.16f,g=0.20f,b=0.30f,a=0f};

                if(popup_action_pressed){
                    action_bg.a = 0.45f;
                } else if(popup_action_hovered){
                    action_bg.a = 0.30f;
                }

                ctx.draw_rect_rounded(popup_x, popup_y, POPUP_W, popup_h, 10f, bg);
                ctx.draw_rect_rounded(popup_x, popup_y, POPUP_W, 1, 10f, border);

                if(popup_h > POPUP_TITLE_H){
                    ctx.draw_rect(popup_x + 10, popup_y + POPUP_TITLE_H, POPUP_W - 20, 1, sep);
                }

                var title = popup_app.title;
                var title_y = popup_y + 26;
                ctx.draw_text(title, popup_x + POPUP_W / 2, title_y, 16f, text);

                if(popup_h > POPUP_TITLE_H + 8){
                    ctx.draw_rect(popup_x + 4, popup_y + POPUP_TITLE_H + 2, POPUP_W - 8, int.max(0, popup_h - POPUP_TITLE_H - 6), action_bg);
                    var action_text = popup_app.is_pinned ? "Unpin" : "Pin";
                    var action_y = popup_y + POPUP_TITLE_H + 26;
                    ctx.draw_text(action_text, popup_x + POPUP_W / 2, action_y, 15f, action);
                }
            }

            private void update_input_region(){
                var size = WLHooks.get_screen_size();
                int extra = tray.get_expanded_height();
                if(is_popup_open() && popup_h > extra) {
                    extra = popup_h + POPUP_GAP;
                }

                var region_y = HEIGHT - EXCLUSIVE_HEIGHT - extra;
                var region_h = EXCLUSIVE_HEIGHT + extra;
                WLHooks.set_input_region(0, region_y, size.width, region_h);
            }
        }