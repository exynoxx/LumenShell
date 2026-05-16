using GLES2;
using DrawKit;
using Gee;

public const int APP_UNDERLINE_Y = HEIGHT - UNDERLINE_HEIGHT;
public const int APP_Y           = HEIGHT - EXCLUSIVE_HEIGHT;
public const int APP_WIDTH       = 70;
public const int APP_HEIGHT      = EXCLUSIVE_HEIGHT;

public class App {
    public int order;
    public string app_id;
    public string title;
    public string launch_cmd;
    public GLuint tex;
    public bool is_pinned;
    public bool is_launcher;
    public bool hovered;
    public bool clicked;
    public bool launching;
    public int x;
    public int y;
    public int tex_x;
    public int tex_y;
    public ArrayList<uint> window_ids;

    private int cycle_idx = 0;

    const int padding_side = (APP_WIDTH - 32) / 2;
    const int padding_top  = (APP_HEIGHT - 32) / 2;

    public App(string app_id, string title, string? launch_cmd, int order, bool is_launcher = false){
        this.app_id      = app_id;
        this.title       = title;
        this.launch_cmd  = launch_cmd ?? "";
        this.is_launcher = is_launcher;
        this.is_pinned   = is_launcher;
        this.y           = APP_Y;
        this.window_ids  = new ArrayList<uint>();

        reset_order(order);
        load_icon();
    }

    public void reset_order(int i){
        this.order  = i;
        this.x      = i * APP_WIDTH + 2;
        this.tex_x  = x + padding_side;
        this.tex_y  = y + padding_top;
    }

    public void mouse_motion(int x, int y){
        var oldval = hovered;
        hovered = hit_test(x, y);
        if (hovered != oldval) redraw = true;
    }

    public bool hit_test(int mx, int my){
        return (mx >= this.x && mx <= this.x + APP_WIDTH
             && my >= this.y && my <= this.y + APP_HEIGHT);
    }

    public void add_window(uint id){
        if (!window_ids.contains(id)) {
            window_ids.add(id);
            launching = false;
        }
    }

    public void remove_window(uint id){
        var idx = window_ids.index_of(id);
        if (idx < 0) return;

        window_ids.remove_at(idx);
        if (window_ids.size == 0) {
            cycle_idx = 0;
            return;
        }

        if (cycle_idx >= window_ids.size)
            cycle_idx = 0;
    }

    public bool has_open_windows(){
        return window_ids.size > 0;
    }

    public uint next_window_for_focus(){
        if (window_ids.size == 0) return 0;
        if (cycle_idx >= window_ids.size) cycle_idx = 0;

        var target = window_ids[cycle_idx];
        cycle_idx = (cycle_idx + 1) % window_ids.size;
        return target;
    }

    public void on_window_focused(uint id){
        var idx = window_ids.index_of(id);
        if (idx < 0 || window_ids.size == 0) return;
        cycle_idx = (idx + 1) % window_ids.size;
    }

    public void set_pinned(bool pinned){
        if (is_launcher) {
            is_pinned = true;
            return;
        }
        is_pinned = pinned;
    }

    public void render(Context ctx){
        var color = Theme.app_hover;
        if (!hovered) color.a = 0f;

        ctx.draw_rect(this.x, this.y, APP_WIDTH, APP_HEIGHT, color);
        ctx.draw_texture(tex, tex_x, tex_y, 32, 32);

        if (launching) {
            ctx.draw_rect(this.x + 9, APP_UNDERLINE_Y, APP_WIDTH - 18, UNDERLINE_HEIGHT, Theme.app_launching);
        }
    }

    public void on_click(){
        if (is_launcher) {
            spawn_kickoff();
            return;
        }

        if (launching) {
            redraw = true;
            return;
        }

        if (has_open_windows()) {
            var id = next_window_for_focus();
            if (id > 0) {
                WLHooks.toplevel_activate_by_id(id);
                redraw = true;
                return;
            }
        }

        launch_new_window();
    }

    public void launch_new_window(){
        if (is_launcher) {
            spawn_kickoff();
            return;
        }

        if (launch_cmd == "") {
            stderr.printf("No launch command for app_id=%s\n", app_id);
            return;
        }

        // Hand the spawned process an XDG activation token so KWin / GNOME /
        // wlroots compositors will grant focus to its first window. No-op if
        // xdg_activation_v1 is unavailable.
        string? token = WLHooks.activation_get_token(app_id);
        if (token != null)
            Environment.set_variable("XDG_ACTIVATION_TOKEN", token, true);

        try {
            Process.spawn_command_line_async(launch_cmd);
            if (is_pinned) launching = true;
        } catch (Error e) {
            launching = false;
            stderr.printf("Launch failed for %s: %s\n", app_id, e.message);
        }

        if (token != null) Environment.unset_variable("XDG_ACTIVATION_TOKEN");

        redraw = true;
    }

    public void close_all_windows(){
        if (window_ids.size == 0) return;

        var ids_to_close = new ArrayList<uint>();
        foreach (var id in window_ids) ids_to_close.add(id);
        foreach (var id in ids_to_close) WLHooks.toplevel_close_by_id(id);
    }

    public void free(){
        DrawKit.texture_free(tex);
    }

    private void spawn_kickoff() {
        try {
            Process.spawn_command_line_async(Utils.KICKOFF_BIN);
        } catch (Error e) {
            stderr.printf("Kickoff exception: %s\n", e.message);
        }
        redraw = true;
    }

    private void load_icon(){
        if (is_launcher) {
            load_svg_icon(Utils.RES_DIR + "app.svg");
            return;
        }

        var icon_path = Utils.get_icon_path_from_app_id(app_id);
        if (icon_path == null) {
            stderr.printf("Icon not found for app_id=%s\n", app_id);
            load_svg_icon(Utils.RES_DIR + "app.svg");
            return;
        }

        if (icon_path.contains(".svg")) {
            var image = DrawKit.image_from_svg(icon_path, 32, 32);
            if (image == null) return;
            tex = DrawKit.texture_upload(*image);
        } else {
            var image = DrawKit.image_load(icon_path);
            tex = DrawKit.texture_upload(image);
        }
    }

    private void load_svg_icon(string path) {
        var image = DrawKit.image_from_svg(path, 32, 32);
        if (image != null)
            tex = DrawKit.texture_upload(*image);
    }
}
