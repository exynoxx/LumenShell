using Gee;
using DrawKit;

public class PageButton {

    private int i;
    private int x;
    private int y;
    private string label;
    private Color color = {0.3f,0.3f,0.3f,1f};
    private Color color_active = {1f,1f,1f,1f};

    public PageButton (int x, int y, int i){
        this.x = x;
        this.y = y;
        this.i = i;
        this.label = (i+1).to_string();
    }
    
    public void render(Context ctx, int active_idx) {
        var color = (i==active_idx)? color_active : color;
        ctx.draw_circle(x,y, 15, color);
        ctx.draw_text(label, x, y+5, 15, {1,1,1,1});
    }
}


public class Navigation {

    private ArrayList<PageButton> pages;

    public Navigation(int count, int screen_width, int screen_height){
        pages = new ArrayList<PageButton>();
        int y = screen_height - 100;
        var total_width = 50*count;
        var offset = (screen_width/2) - (total_width/2);

        for (int i = 0; i < count; i++){
            pages.add(new PageButton(offset+50*i, y, i));
        }
    }

    public void render(Context ctx, int active_idx) {
        foreach (var page in pages){
            page.render(ctx, active_idx);
        }
    } 



}


