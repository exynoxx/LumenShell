using DrawKit;

public class SearchBar {

    private int x;
    private int y = 50;
    private const int width = 250;
    private const int height = 30;
    private const string label = "Search";
    private int label_x;

    public SearchBar(Context ctx, int screen_center_x){
        this.x = screen_center_x - width/2;
        this.label_x = screen_center_x;
    }

    public void render(Context ctx){
        ctx.draw_rect_rounded(x, y, width, height, 4f, {0.9f,0.9f,0.9f,0.75f});
        ctx.draw_text("Search", this.label_x, y+20, 18, {0f,0f,0f,1f});
    }
}