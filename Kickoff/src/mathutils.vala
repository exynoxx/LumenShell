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
            int page_i = i % (GRID_ROWS * GRID_COLS);

            int row = page_i / GRID_COLS;
            int col = page_i % GRID_COLS;

            var grid_x = page*screen_width + PADDING_EDGES_X + col * padding_h + col * ICON_SIZE;
            var grid_y = PADDING_EDGES_Y + row * padding_v + row * ICON_SIZE;


            
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

}

//O(1) app hover algo
/*  public Tile? find_hovered_tile_grid(Gee.ArrayList<Tile> tiles,
    int mouse_x, int mouse_y,
    int screen_width, int screen_height) {
// Calculate which grid cell the mouse is in
int gaps_h = GRID_COLS + 1;
int gaps_v = GRID_ROWS + 1;

var padding_h = (screen_width - GRID_COLS * ICON_SIZE) / gaps_h;
var padding_v = (screen_height - GRID_ROWS * ICON_SIZE) / gaps_v;

int cell_width = ICON_SIZE + padding_h;
int cell_height = ICON_SIZE + padding_v;

// Determine page
int page = mouse_x / screen_width;
int page_x = mouse_x % screen_width;

// Calculate row and column
int col = (page_x - PADDING_EDGES_X) / cell_width;
int row = (mouse_y - PADDING_EDGES_Y) / cell_height;

// Bounds check
if (col < 0 || col >= GRID_COLS || row < 0 || row >= GRID_ROWS) {
return null;
}

// Calculate tile index
int tile_index = page * (GRID_ROWS * GRID_COLS) + row * GRID_COLS + col;

if (tile_index >= tiles.size) return null;

// Verify the point is actually inside (not in padding)
var tile = tiles[tile_index];
if (tile.contains_point(mouse_x, mouse_y)) {
return tile;
}

return null;
}  */