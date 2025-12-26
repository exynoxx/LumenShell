using DrawKit;

public class SearchBar {

    private int x;
    private int y = 50;
    private const int width = 250;
    private const int height = 30;
    private int label_x;
    private unowned Context ctx;

    public SearchBar(Context ctx, int screen_width){
        var screen_center_x = screen_width / 2;
        this.x = screen_center_x - width/2;
        this.label_x = screen_center_x;
        this.ctx = ctx;
    }

    public void render(string label){
        ctx.draw_rect_rounded(x, y, width, height, 4f, {0.9f,0.9f,0.9f,0.75f});
        ctx.draw_text(label, this.label_x, y+20, 18, {0f,0f,0f,1f});
    }
}