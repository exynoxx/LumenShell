using DrawKit;

public class IconAndText : Object, ITray, IHoverable, IExpandable {

    // Each instance gets unique animation IDs so transitions don't overwrite each other
    private static int _next_anim_id = 20;
    private int anim_id;

    protected int base_width;
    protected int max_width;
    protected int width;

    protected int x;
    protected int y;

    protected int text_x;
    protected int text_y;
    private int text_margin_top;   // vertical offset to centre text in tray bar

    private unowned Context ctx;
    public HoverableIcon icon;

    protected string text;

    public IconAndText(Context ctx, HoverableIcon icon, string label){
        anim_id = _next_anim_id;
        _next_anim_id += 1;

        this.ctx = ctx;
        this.icon = icon;
        this.text = label;

        base_width = icon.get_width();
        _recalc_max_width();
        width = base_width;

        // Centre text vertically inside the tray pill (same logic as Clock)
        text_margin_top = (Tray.TRAY_HEIGHT - ctx.height_of(label, FONT_SIZE)) / 2;
    }

    private void _recalc_max_width() {
        int text_w = ctx.width_of(text, FONT_SIZE);
        // add small padding on each side of text
        max_width = base_width + text_w + 12;
    }

    // Call from subclasses when the display text changes at runtime
    protected void set_text(string new_text) {
        text = new_text;
        _recalc_max_width();
        // If currently expanded beyond the new max, contract to new max immediately
        if (width > max_width)
            width = max_width;
    }

    // set_position is called by the Tray container every frame during animation.
    // We keep the ICON at the RIGHT end of our expanded area so it appears stationary
    // while text grows out to the left.
    public void set_position(int x, int y){
        this.x = x;
        this.y = y;
        // icon right-anchored: offset from x by the extra expansion
        icon.set_position(x + (width - base_width), y);
        // text appears on the left side of the expanded area
        text_x = x + 4;
        text_y = y + text_margin_top + 5;   // +5 matches the Clock baseline nudge
    }

    public int get_width(){
        return width;
    }

    public int get_max_width(){
        return max_width;
    }

    // IHoverable — also triggers expand/contract automatically
    public void mouse_motion(int mouse_x, int mouse_y){
        var was_hovered = icon.hovered;
        icon.mouse_motion(mouse_x, mouse_y);
        var is_hovered = icon.hovered;

        if (!was_hovered && is_hovered)  expand();
        if (was_hovered  && !is_hovered) contract();
    }

    // IExpandable
    public void expand(){
        animations.add(new Transition1D(anim_id, &width, max_width, 0.25d));
        redraw = true;
    }

    public void contract(){
        animations.add(new Transition1D(anim_id, &width, base_width, 0.25d));
        redraw = true;
    }

    public void render(Context ctx){
        this.icon.render(ctx);
        if (width > base_width) {
            // fade text in as the area opens
            float progress = float.min(1.0f,
                (float)(width - base_width) / (float)(max_width - base_width) * 2.5f);
            ctx.draw_text(text, text_x, text_y, FONT_SIZE, {1, 1, 1, progress});
        }
    }

}