using DrawKit;

public class IconAndText : Object, ITray, IHoverable, IExpandable {

    protected int base_width;
    protected int max_width;
    protected int width;

    protected int x;
    protected int y;

    protected int text_x;
    protected int text_y;
    private int text_width;

    public HoverableIcon icon;
    protected Transition transition;
    
    protected string text;

    public IconAndText(Context ctx, HoverableIcon icon, string label){
        this.icon = icon;
        this.text = label;

        text_width = ctx.width_of(label, FONT_SIZE);

        width = base_width = icon.get_width();
        max_width = base_width + text_width;

        text_x = base_width;
    }

    public void set_position(int x, int y){
        icon.set_position(x, y);
        this.x = x;
        this.y = y;
        text_x = x + base_width;
        text_y = y+10;
    }

    public int get_width(){
        return width;
    }
    public int get_max_width(){
        return max_width;
    }

    public void mouse_motion(int mouse_x, int mouse_y){
        icon.mouse_motion(mouse_x, mouse_y);
    }

    public void expand(){
        transition = new Transition1D(2, &width, max_width, 1d);
        animations.add(transition);
        animations.add(new Transition1D(2, &x, x-text_width, 1d));
    }

    public void contract(){
        transition = new Transition1D(2, &width, base_width, 1d);
        animations.add(transition);
        animations.add(new Transition1D(2, &x, x+text_width, 1d));
    }

    public void render(Context ctx){
        this.icon.render(ctx);
        if(width>base_width)
            ctx.draw_text(text, text_x, text_y, FONT_SIZE, {1,1,1,1});
    }

}