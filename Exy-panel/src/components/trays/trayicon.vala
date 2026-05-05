using DrawKit;
using GLES2;

public interface ITray : GLib.Object{
    public abstract int get_width();
    public abstract void set_position(int x, int y);
    public abstract void mouse_down();
    public abstract void mouse_up();
    public abstract void mouse_motion(int mouse_x, int mouse_y);
    public abstract void render(Context ctx);
}

public abstract class TrayIcon : Object, ITray {

    private const string base_path = "/home/nicholas/Dokumenter/layer-shell-experiments/Exy-panel/src/res/";
    protected const int ICON_SIZE = 32;
    private const int HOVER_RADIUS = 24;
    protected const int COLLAPSED_WIDTH = HOVER_RADIUS * 2;
    private const int EXPANDED_WIDTH = 180;
    // Minimum expansion in pixels before detail content is drawn (avoids a one-frame flash).
    protected const int MIN_EXPAND_THRESHOLD = 4;
    private const int MARGIN_TOP = (Tray.TRAY_HEIGHT - ICON_SIZE)/2;

    // Each TrayIcon instance gets a unique animation slot ID.
    // Start at 100 to avoid collisions with Tray's own animation IDs (0, 1).
    private static int anim_id_counter = 100;
    protected int anim_id;

    protected GLuint tex;
    protected bool hovered;
    protected bool expanded = false;

    // Adjusted drawing position (after MARGIN_TOP is applied).
    protected int render_x;
    protected int render_y;
    private int circle_x;
    private int circle_y;

    // Animated width: starts collapsed, grows to get_expanded_width() on click.
    protected int current_width;

    protected TrayIcon(string icon){
        load(icon);
        current_width = COLLAPSED_WIDTH;
        anim_id = anim_id_counter++;
    }

    public int get_width() {
        return current_width;
    }

    public void set_position(int x, int y){
        this.render_x = x;
        this.render_y = y + MARGIN_TOP;
        this.circle_x = render_x + ICON_SIZE/2;
        this.circle_y = render_y + ICON_SIZE/2;
    }

    // Returns the target width when this icon is expanded.
    // Subclasses can override for a wider slot.
    protected virtual int get_expanded_width() {
        return EXPANDED_WIDTH;
    }

    public void load(string icon){

        var path = Path.build_filename(base_path, icon+".svg");

        var image = DrawKit.image_from_svg(path,ICON_SIZE,ICON_SIZE);
        if(image == null){
            print("Launcher icon not found\n");
            return;
        }

        tex = DrawKit.texture_upload(*image);
    }

    public void free(){
        DrawKit.texture_free(tex);
    }

    // Returns the detail string shown when this icon is expanded.
    // Subclasses override to provide meaningful text; empty string disables expansion.
    protected virtual string get_detail_text() {
        return "";
    }

    public virtual void mouse_motion(int mouse_x, int mouse_y){
        var hover_initial = hovered;

        hovered = (
            mouse_x >= circle_x - HOVER_RADIUS && 
            mouse_x <= circle_x + HOVER_RADIUS && 
            mouse_y >= circle_y - HOVER_RADIUS && 
            mouse_y <= circle_y + HOVER_RADIUS);

        if(hovered != hover_initial) 
            redraw = true;
    }

    // Default: toggle expansion when clicked while hovered (if detail text is available).
    // Subclasses that need different behaviour should override without calling base.
    public virtual void mouse_down(){
        if(hovered && get_detail_text() != "") {
            expanded = !expanded;
            int target = expanded ? get_expanded_width() : COLLAPSED_WIDTH;
            animations.add(new Transition1D(anim_id, &current_width, target, 0.4));
            redraw = true;
        }
    }

    public virtual void mouse_up(){}

    // Draw the icon and its hover highlight; available for subclasses that override render()
    // but still want the standard icon appearance.
    protected void render_icon(Context ctx){
        if(hovered){
            ctx.draw_circle(circle_x, circle_y, 24, {1,1,1,1});
            ctx.set_tex_color({0,0,0,1});
            ctx.draw_texture(tex, render_x, render_y, ICON_SIZE, ICON_SIZE);
            ctx.set_tex_color({1,1,1,1});
        } else {
            ctx.draw_texture(tex, render_x, render_y, ICON_SIZE, ICON_SIZE);
        }
    }

    public virtual void render(Context ctx){
        render_icon(ctx);

        // Draw detail text to the right of the icon as the slot expands.
        // Wait for a small amount of expansion before drawing to avoid a one-frame flash.
        if(current_width > COLLAPSED_WIDTH + MIN_EXPAND_THRESHOLD) {
            float progress = float.min(
                (float)(current_width - COLLAPSED_WIDTH) / (float)(get_expanded_width() - COLLAPSED_WIDTH),
                1.0f);

            string detail = get_detail_text();
            if(detail != "") {
                // Centre the text in the expanded area to the right of the icon.
                int text_area_left = render_x + ICON_SIZE + 8;
                int text_area_width = current_width - ICON_SIZE - 8;
                int text_center_x = text_area_left + text_area_width / 2;
                int text_y = render_y + ICON_SIZE / 2 + 4;
                ctx.draw_text(detail, text_center_x, text_y, 13, {1, 1, 1, progress});
            }
        }
    }
}