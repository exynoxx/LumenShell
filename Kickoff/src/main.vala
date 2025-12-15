using DrawKit;
using WLHooks;
using GLES2;

namespace Main {

    public static bool redraw = true;
    public static void queue_redraw(){
        redraw = true;
    }

    static AppLauncher? launcher = null;
    public static AnimationManager animations;
    
    static int main(string[] args) {
    
        WLHooks.grab_keyboard(true);
        WLHooks.init();

        var size = WLHooks.get_screen_size();
        print("WLHooks - screen size: %i %i\n", size.width, size.height);
        
        WLHooks.init_layer_shell("Kickoff-overlay", size.width, size.height, UP | LEFT | RIGHT | DOWN, false);
  
        animations = new AnimationManager();
        launcher = new AppLauncher(size.width, size.height);

        WLHooks.register_on_mouse_down(launcher.mouse_down);
        WLHooks.register_on_mouse_up(launcher.mouse_up);
        WLHooks.register_on_mouse_motion(launcher.mouse_move); //fix double
        WLHooks.register_on_key_down(key=> {
            if(key == 65307){
                WLHooks.destroy();
                Process.exit (0);
            }
            launcher.key_down(key);
        });
        
        while (WLHooks.display_dispatch_blocking() != -1) {
            if(redraw || animations.has_active){
                animations.update();
                launcher.render();
                WLHooks.swap_buffers();
                redraw = false;
            }
        }
    
        WLHooks.destroy();
        return 0;
    }
}
