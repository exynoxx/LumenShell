using Gee;

public class Position {
    public int x;
    public int y;

    public Position(int x, int y){
        this.x = x;
        this.y = y;
    }
}

public class MathUtils {

    //consts in applauncher.vala

    public static HashMap<int, Position> Calculate_grid_positions(int screen_width, int screen_height, int num_grid_positions) {
        
        var r = new HashMap<int,Position>();

        int gaps_h = GRID_COLS + 1;
        int gaps_v = GRID_ROWS + 1;

        var padding_h = (screen_width - GRID_COLS*ICON_SIZE) / gaps_h;
        var padding_v = (screen_height - GRID_ROWS*ICON_SIZE) / gaps_v;

        for (int i = 0; i < num_grid_positions; i++)
        {
            int page = i / (GRID_ROWS * GRID_COLS);
            int row = i / GRID_COLS;
            int col = i % GRID_COLS;

            var grid_x = page*screen_width + PADDING_EDGES_X + col * padding_h + col * ICON_SIZE;
            var grid_y = PADDING_EDGES_Y + row * padding_v + row * ICON_SIZE;


            
            r[i] = new Position(grid_x, grid_y); 
        }

        return r;
    }

}