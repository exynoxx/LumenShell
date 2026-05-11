using WLHooks;
using GLES2;
using Gee;

public static bool redraw = true;
public static AnimationManager animations;

public static int main(string[] args) {

    Theme.load();

    WLHooks.grab_keyboard(true);   // must be set before init so seat binds keyboard
    WLHooks.init();

    var panel = new Panel();
    animations = new AnimationManager();

    WLHooks.register_on_window_new(panel.on_window_new);
    WLHooks.register_on_window_rm(panel.on_window_rm);
    WLHooks.register_on_window_focus(panel.on_window_focus);

    WLHooks.register_on_mouse_down(panel.on_mouse_down);
    WLHooks.register_on_mouse_up(panel.on_mouse_up);
    WLHooks.register_on_mouse_motion(panel.on_mouse_motion);
    WLHooks.register_on_mouse_leave(panel.on_mouse_leave);
    WLHooks.register_on_mouse_scroll(panel.on_mouse_scroll);

    while (WLHooks.display_dispatch_blocking() != -1) {
        if(redraw || animations.has_active){
            animations.update();
            panel.render();
            WLHooks.swap_buffers();
            redraw = false;
        }
    }

    WLHooks.destroy();
    return 0;
}
