using DrawKit;
using GLES2;

public class HoverableIcon : IHoverable, ITray, Object {

    private const int ICON_SIZE   = 32;
    private const int HOVER_RADIUS = 24;
    private const int MARGIN_TOP  = (Tray.TRAY_HEIGHT - ICON_SIZE) / 2;

    protected GLuint tex = 0;
    private int x;
    private int y;
    private int circle_x;
    private int circle_y;
    public bool hovered;
    public bool selected;

    public HoverableIcon(string icon){
        set_icon(icon);
    }

    public int get_width(){
        return HOVER_RADIUS * 2;
    }

    public void mouse_motion(int mouse_x, int mouse_y){
        var hover_initial = hovered;

        hovered = IHoverable.is_hover(
            circle_x - HOVER_RADIUS, circle_y - HOVER_RADIUS,
            HOVER_RADIUS * 2,        HOVER_RADIUS * 2,
            mouse_x, mouse_y);
        if (hovered != hover_initial)
            redraw = true;
    }

    public void set_position(int x, int y){
        this.x        = x;
        this.y        = y + MARGIN_TOP;
        this.circle_x = this.x + ICON_SIZE / 2;
        this.circle_y = this.y + ICON_SIZE / 2;
    }

    public bool set_icon(string icon){
        var path  = Path.build_filename(Utils.RES_DIR, icon + ".svg");
        var image = DrawKit.image_from_svg(path, ICON_SIZE, ICON_SIZE);
        if (image == null) {
            print("Icon file not found: %s\n", path);
            return false;
        }

        var next_tex = DrawKit.texture_upload(*image);
        if (next_tex == 0) {
            print("Failed to upload icon texture: %s\n", path);
            return false;
        }

        if (tex != 0)
            DrawKit.texture_free(tex);

        tex = next_tex;
        return true;
    }

    public void free(){
        if (tex != 0) {
            DrawKit.texture_free(tex);
            tex = 0;
        }
    }

    public void render(Context ctx){
        if (tex == 0) return;

        if (hovered || selected) {
            ctx.draw_circle(circle_x, circle_y, 24, {0.16f, 0.18f, 0.26f, 1f});
            ctx.set_tex_color({1f, 1f, 1f, 1f});
            ctx.draw_texture(tex, x, y, ICON_SIZE, ICON_SIZE);
        } else {
            ctx.draw_texture(tex, x, y, ICON_SIZE, ICON_SIZE);
        }
    }
}
