public interface IGrid {
    public abstract void mouse_move(int mouse_x, int mouse_y);
    public abstract void mouse_down();
    public abstract void mouse_up();
    public abstract void key_down(uint32 key);
    public abstract void render();
}