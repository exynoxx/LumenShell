using DrawKit;

public class UiScrollView : GLib.Object {

    private int area_x = 0;
    private int area_y = 0;
    private int area_w = 0;
    private int area_h = 0;

    private int row_h = 1;
    private int item_count = 0;
    private int first_row = 0;

    public void reset() {
        first_row = 0;
        item_count = 0;
    }

    public void update_layout(int x, int y, int w, int h, int row_height, int items) {
        area_x = x;
        area_y = y;
        area_w = int.max(0, w);
        area_h = int.max(0, h);
        row_h = int.max(1, row_height);
        item_count = int.max(0, items);
        clamp_first_row();
    }

    public bool contains(int mx, int my) {
        return mx >= area_x && mx <= area_x + area_w
            && my >= area_y && my <= area_y + area_h;
    }

    public int visible_rows() {
        return row_h > 0 ? area_h / row_h : 0;
    }

    public int first_visible_row() {
        return first_row;
    }

    public bool can_scroll() {
        return item_count > visible_rows();
    }

    public bool scroll_lines(int delta) {
        if (delta == 0) return false;
        int old = first_row;
        first_row += delta;
        clamp_first_row();
        return old != first_row;
    }

    public void ensure_visible(int index) {
        int rows = visible_rows();
        if (index < 0 || index >= item_count || rows <= 0) return;

        if (index < first_row) {
            first_row = index;
        } else if (index >= first_row + rows) {
            first_row = index - rows + 1;
        }
        clamp_first_row();
    }

    public int row_at(int mx, int my) {
        if (!contains(mx, my)) return -1;

        int rows = visible_rows();
        if (rows <= 0) return -1;

        int rel = (my - area_y) / row_h;
        if (rel < 0 || rel >= rows) return -1;

        int idx = first_row + rel;
        return idx < item_count ? idx : -1;
    }

    public int draw_y_for(int index) {
        return area_y + (index - first_row) * row_h;
    }

    public void render_scrollbar(Context ctx) {
        int rows = visible_rows();
        if (item_count <= rows || rows <= 0 || area_h <= 8) return;

        int track_x = area_x + area_w - 6;
        int track_y = area_y + 2;
        int track_w = 4;
        int track_h = area_h - 4;

        ctx.draw_rect_rounded(track_x, track_y, track_w, track_h, 2f,
            Color(){r=0.18f, g=0.19f, b=0.26f, a=0.75f});

        int thumb_h = (track_h * rows) / item_count;
        thumb_h = int.max(16, thumb_h);
        thumb_h = int.min(track_h, thumb_h);

        int max_off = item_count - rows;
        int thumb_range = track_h - thumb_h;
        int thumb_y = track_y;
        if (max_off > 0 && thumb_range > 0) {
            thumb_y += (first_row * thumb_range) / max_off;
        }

        ctx.draw_rect_rounded(track_x, thumb_y, track_w, thumb_h, 2f,
            Color(){r=0.34f, g=0.36f, b=0.47f, a=0.92f});
    }

    private void clamp_first_row() {
        int max_off = int.max(0, item_count - visible_rows());
        first_row = int.max(0, int.min(first_row, max_off));
    }
}
