using Gee;
using DrawKit;

public class PageButton {

    private int x;
    private int y;
    private string label;
    private Color color = {0.3f,0.3f,0.3f,1f};

    public PageButton (int x, int y, string label){
        this.x = x;
        this.y = y;
        this.label = label;
    }
    
    public void render(Context ctx) {
        ctx.draw_circle(x,y, 15, color);
        ctx.draw_text(label, x, y+5, 15);
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
            pages.add(new PageButton(offset+50*i, y, (i+1).to_string()));
        }
    }

    public void render(Context ctx) {
        foreach (var page in pages){
            page.render(ctx);
        }
    } 



}


