using DrawKit;

public class UiSignalBars : GLib.Object {

    public Color good_color = Color(){r=0.18f, g=0.85f, b=0.40f, a=1f};
    public Color medium_color = Color(){r=1.0f, g=0.72f, b=0.10f, a=1f};
    public Color low_color = Color(){r=1.0f, g=0.30f, b=0.30f, a=1f};
    public Color dim_color = Color(){r=0.20f, g=0.21f, b=0.28f, a=0.75f};

    private int[] heights = { 6, 10, 14, 20 };

    public void render(Context ctx, int left_x, int bottom_y, int signal) {
        int active = signal >= 75 ? 4 : signal >= 50 ? 3 : signal >= 25 ? 2 : 1;

        Color active_col = signal >= 65
            ? good_color
            : signal >= 35 ? medium_color : low_color;

        for (int i = 0; i < 4; i++) {
            int bh = heights[i];
            int bx = left_x + i * 7;
            int by = bottom_y - bh;
            ctx.draw_rect_rounded(bx, by, 4, bh, 2f,
                i < active ? active_col : dim_color);
        }
    }
}
