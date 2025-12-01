using DrawKit;
using WLHooks;
using GLES2;

namespace Main {

    public static bool redraw = true;
    public static bool draw_lock = false;
    public static void queue_redraw(){
        redraw = true;
    }
    
    static AppLauncher? launcher = null;
    
    static int main(string[] args) {
    
        WLHooks.grab_keyboard(true);
        WLHooks.init_layer_shell("Kickoff-overlay", 1920, 1080, UP | LEFT | RIGHT | DOWN, false);
    
        var size = WLHooks.get_layer_shell_size();
        print("layer shell size: %i %i\n", size.width, size.height);

        launcher = new AppLauncher(/*  size.width, size.height  */1920, 1080);
    
        WLHooks.register_on_mouse_down(launcher.mouse_down);
        WLHooks.register_on_mouse_up(launcher.mouse_up);
        WLHooks.register_on_mouse_motion(launcher.mouse_move); //fix double
        WLHooks.register_on_key_down(key=> {
            if(key == 65307){
                WLHooks.destroy();
                Process.exit (0);
            }
            print("Key %d\n", (int) key);
        });
        
        while (WLHooks.display_dispatch_blocking() != -1) {
            
            if(redraw || Main.draw_lock){
                launcher.render();
                WLHooks.swap_buffers();
                redraw = false;
            }
        }
    
        WLHooks.destroy();
        return 0;
    }
}
