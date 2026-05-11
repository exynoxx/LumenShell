using DrawKit;
using Gee;

public const int HEIGHT          = 554;
public const int EXCLUSIVE_HEIGHT = 60;
public const int UNDERLINE_HEIGHT = 5;

public const uint32 BTN_LEFT  = 272;
public const uint32 BTN_RIGHT = 273;

public const int POPUP_ANIM_ID  = 200;
public const int POPUP_W        = 220;
public const int POPUP_ROW_H    = 32;
public const int POPUP_GAP      = 8;
public const int POPUP_TITLE_H  = 42;

public class Panel {

    private ArrayList<App> entries;
    private HashMap<string, App> app_index;
    private HashMap<uint, App> window_index;

    private uint active_window_id;
    private int  screen_width;

    private Context  ctx;
    private Tray     tray;
    private AppPopup popup;

    private string pins_file;

    private int last_mouse_x = -1;
    private int last_mouse_y = -1;

    // Track last values so update_input_region only calls WLHooks when they change
    private int last_region_extra = -1;

    private Color active_underline = Theme.app_active_underline;

    public Panel(){
        var size = WLHooks.get_screen_size();
        screen_width = size.width;

        WLHooks.init_layer_shell("panel", screen_width, HEIGHT, BOTTOM, true, EXCLUSIVE_HEIGHT);

        ctx = new DrawKit.Context(screen_width, HEIGHT);
        ctx.set_bg_color(DrawKit.Color(){r=0, g=0, b=0, a=0});

        entries      = new ArrayList<App>();
        app_index    = new HashMap<string, App>();
        window_index = new HashMap<uint, App>();

        var kickoff = new App("--", "Launcher", "", 0, true);
        entries.add(kickoff);

        tray  = new Tray(ctx, screen_width);
        popup = new AppPopup(screen_width);

        popup.pin_toggled.connect((app) => {
            app.set_pinned(!app.is_pinned);
            save_pins();
            if (!app.is_pinned && !app.has_open_windows())
                remove_app(app);
            relayout();
            redraw = true;
        });
        popup.new_window_requested.connect((app) => {
            app.launch_new_window();
            redraw = true;
        });
        popup.close_windows_requested.connect((app) => {
            app.close_all_windows();
            redraw = true;
        });

        pins_file = Path.build_filename(Environment.get_user_config_dir(), "lumen-panel", "pinned-apps.txt");
        load_pins();
        relayout();
        update_input_region();
    }

    public void on_window_new(uint id, string app_id, string title){
        var item = get_or_create_app(app_id, title);
        item.add_window(id);
        window_index[id] = item;
        if (item.title == app_id || item.title == "")
            item.title = title;
        relayout();
        redraw = true;
    }

    public void on_window_rm(uint window_id){
        if (!window_index.has_key(window_id)) return;

        var item = window_index[window_id];
        item.remove_window(window_id);
        window_index.unset(window_id);

        if (active_window_id == window_id)
            active_window_id = 0;

        if (!item.is_launcher && !item.is_pinned && !item.has_open_windows()) {
            if (popup.app == item) popup.hide();
            remove_app(item);
        }

        relayout();
        redraw = true;
    }

    public void on_window_focus(uint id){
        if (!window_index.has_key(id)) return;
        active_window_id = id;
        window_index[id].on_window_focused(id);
        redraw = true;
    }

    public void on_mouse_down(uint32 button){
        if (button == BTN_RIGHT) {
            var hovered = get_hovered_app();
            if (hovered != null && !hovered.is_launcher) {
                popup.show_for(hovered);
                hovered.clicked = true;
                update_input_region();
                redraw = true;
                return;
            }
            popup.hide();
            update_input_region();
            return;
        }

        if (button != BTN_LEFT) return;

        if (popup.is_open()) {
            if (popup.on_mouse_down(last_mouse_x, last_mouse_y)) return;
            popup.hide();
            update_input_region();
        }

        foreach (var app in entries) {
            if (app.hovered && !app.clicked) {
                app.clicked = true;
                app.on_click();
                redraw = true;
                return;
            }
        }

        tray.on_mouse_down();
    }

    public void on_mouse_up(uint32 button){
        if (button != BTN_LEFT && button != BTN_RIGHT) return;

        if (button == BTN_LEFT && popup.is_open()) {
            if (popup.on_mouse_up(last_mouse_x, last_mouse_y)) {
                popup.hide();
                update_input_region();
                redraw = true;
                return;
            }
        }

        foreach (var app in entries) app.clicked = false;
        if (button == BTN_LEFT) tray.on_mouse_up();
    }

    public void on_mouse_motion(int x, int y){
        last_mouse_x = x;
        last_mouse_y = y;

        popup.on_mouse_motion(x, y);

        foreach (var app in entries) app.mouse_motion(x, y);
        tray.on_mouse_motion(x, y);

        update_input_region();
    }

    public void on_mouse_leave(){
        foreach (var app in entries) app.hovered = false;
        popup.hide();
        update_input_region();
        redraw = true;
        tray.on_mouse_leave();
    }

    public void on_mouse_scroll(int amount){
        tray.on_mouse_scroll(amount);
    }

    public void render(){
        ctx.begin_frame();

        ctx.draw_rect(0, APP_Y, screen_width, EXCLUSIVE_HEIGHT, Theme.panel_bg);

        foreach (var app in entries)
            app.render(ctx);

        if (active_window_id > 0 && window_index.has_key(active_window_id)) {
            var active = window_index[active_window_id];
            ctx.draw_rect(active.x, APP_UNDERLINE_Y, APP_WIDTH, UNDERLINE_HEIGHT, active_underline);
        }

        popup.render(ctx);
        tray.render();

        // Update input region only when the animated extents have changed
        int extra = int.max(tray.get_expanded_height(), popup.get_height() > 0 ? popup.get_height() + POPUP_GAP : 0);
        if (extra != last_region_extra) {
            last_region_extra = extra;
            int region_y = HEIGHT - EXCLUSIVE_HEIGHT - extra;
            int region_h = EXCLUSIVE_HEIGHT + extra;
            WLHooks.set_input_region(0, region_y, screen_width, region_h);
        }

        DrawKit.Context.end_frame();
    }

    // ─────────────────────────────────────────────────────────────────────
    // App management
    // ─────────────────────────────────────────────────────────────────────

    private App? get_hovered_app(){
        foreach (var app in entries) {
            if (app.hovered) return app;
        }
        return null;
    }

    private App get_or_create_app(string app_id, string fallback_title){
        if (app_index.has_key(app_id)) return app_index[app_id];

        var name   = Utils.get_display_name_from_app_id(app_id);
        if (name == app_id && fallback_title != "") name = fallback_title;

        var launch = Utils.get_launch_cmd_from_app_id(app_id);
        var item   = new App(app_id, name, launch, entries.size, false);

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
        for (int i = 0; i < entries.size; i++)
            entries[i].reset_order(i);
    }

    private void load_pins(){
        var pins = Ini.read_lines(pins_file);
        foreach (var app_id in pins) {
            if (app_id == "" || app_id == "--") continue;
            if (app_index.has_key(app_id)) continue;

            var name   = Utils.get_display_name_from_app_id(app_id);
            var launch = Utils.get_launch_cmd_from_app_id(app_id);
            var app    = new App(app_id, name, launch, entries.size, false);
            app.set_pinned(true);
            entries.add(app);
            app_index[app_id] = app;
        }
    }

    private void save_pins(){
        var pins = new ArrayList<string>();
        foreach (var app in entries) {
            if (app.is_pinned && !app.is_launcher)
                pins.add(app.app_id);
        }
        Ini.write_lines(pins_file, pins);
    }

    private void update_input_region(){
        int extra = int.max(tray.get_expanded_height(), popup.get_height() > 0 ? popup.get_height() + POPUP_GAP : 0);
        if (extra == last_region_extra) return;
        last_region_extra = extra;
        int region_y = HEIGHT - EXCLUSIVE_HEIGHT - extra;
        int region_h = EXCLUSIVE_HEIGHT + extra;
        WLHooks.set_input_region(0, region_y, screen_width, region_h);
    }
}
