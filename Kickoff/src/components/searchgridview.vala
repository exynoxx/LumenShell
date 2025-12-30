using GLib;
using DrawKit;
using Gee;

public class SearchGridView : IGrid {
    
    private unowned Context ctx;
    private AppView[] apps;
    private int size;

    public SearchGridView(Context ctx, int screen_width, int screen_height) {
        this.ctx = ctx;
        this.apps = new AppView[PER_PAGE];
        var grid_positions = Utils.Math.calculate_grid_positions(screen_width, screen_height, PER_PAGE);
        
        for (int i = 0; i < PER_PAGE; i++){
            var pos = grid_positions[i];
            this.apps[i] = new AppView(pos.x, pos.y);
        }
    }

    public void mouse_move(int mouse_x, int mouse_y) {
        for(int i = 0; i < size; i++)
            apps[i].mouse_move(mouse_x, mouse_y);
    }

    public void mouse_down() {
        for(int i = 0; i < size; i++)
            apps[i].mouse_down();
    }
    public void mouse_up() {
        for(int i = 0; i < size; i++)
            apps[i].mouse_up();
    }

    public void key_down(uint32 key){
        switch (key){
            case KEY_ENTER: 
                apps[0].click();
                break;
            case KEY_1:
                apps[0].click();
                break;
            case KEY_2:
                apps[1].click();
                break;
            case KEY_3:
                apps[2].click();
                break;
        }
    }

    public void render(){
        for(int i = 0; i < size; i++)
            apps[i].render(ctx);
    }
    
    public void add(Utils.AliasArray<AppEntry> apps, int number){
        size = number;
        for (int i = 0; i < size; i++){
            this.apps[i].set_properties(ctx, apps[i]);
        }
    }
}