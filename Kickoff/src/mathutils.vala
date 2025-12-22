using Gee;

public class Position {
    public int x;
    public int y;

    public Position(int x, int y){
        this.x = x;
        this.y = y;
    }
}

//consts in applauncher.vala
public class MathUtils {

    public static HashMap<int, Position> Calculate_grid_positions(int screen_width, int screen_height, int num_grid_positions) {

        var r = new HashMap<int,Position>();

        int gaps_h = GRID_COLS + 1;
        int gaps_v = GRID_ROWS + 1;

        var padding_h = (screen_width - GRID_COLS*ICON_SIZE) / gaps_h;
        var padding_v = (screen_height - GRID_ROWS*ICON_SIZE) / gaps_v;

        for (int i = 0; i < num_grid_positions; i++)
        {
            int page = i / (GRID_ROWS * GRID_COLS);
            int page_i = i % (GRID_ROWS * GRID_COLS);

            int row = page_i / GRID_COLS;
            int col = page_i % GRID_COLS;

            var grid_x = page*screen_width +    PADDING_EDGES_X + col * (ICON_SIZE+padding_h);
            var grid_y =                        PADDING_EDGES_Y + row * (ICON_SIZE+padding_v);
            
            r[i] = new Position(grid_x, grid_y); 
        }

        return r;
    }

    public static void identity_matrix(float *mat) {
        mat[0]  = 1.0f;
        mat[5]  = 1.0f;
        mat[10] = 1.0f;
        mat[15] = 1.0f;
    }
    
    public static void translation_matrix_new(float *mat, float x, float y) {
        identity_matrix(mat);
        mat[12] = x;
        mat[13] = y;
    }

    public static void translation_matrix(float *mat, float x, float y) {
        mat[12] = x;
        mat[13] = y;
    }

    //translate(x,y) * zoom(factor) * translate(-x,-y)
    public static void centered_zoom_marix(float *mat, int screen_center_x, int screen_center_y, float zoom_factor){
        mat[0] = zoom_factor;
        mat[5] = zoom_factor;
        mat[10] = 1;
        mat[12] = screen_center_x * (1 - zoom_factor);
        mat[13] = screen_center_y * (1 - zoom_factor);
        mat[15] = 1;
    }

    //O(1) mouse hover
    /*  public static int tile_index_from_mouse(int mouse_x, int mouse_y, int active_page)
    {
        int gx = mouse_x - PADDING_EDGES_X;
        int gy = mouse_y - PADDING_EDGES_Y;
    
        if (gx < 0 || gy < 0)
            return -1;
    
        int col = gx / (ICON_SIZE + padding_h);
        int row = gy / (ICON_SIZE + padding_v);
    
        if (col < 0 || col >= GRID_COLS)
            return -1;
        if (row < 0 || row >= GRID_ROWS)
            return -1;
      
        int inside_x = gx % (ICON_SIZE + padding_h);
        int inside_y = gy % (ICON_SIZE + padding_v);
    
        if (inside_x >= ICON_SIZE || inside_y >= ICON_SIZE)
            return -1;
      
        return active_page * PER_PAGE + row * GRID_COLS + col;
    }  */

}