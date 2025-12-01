using DrawKit;
using WLUnstable;
using GLES2;

namespace Main {

    
    
    static AppLauncher? launcher = null;
    
    static int main(string[] args) {
    
        WLUnstable.grab_keyboard(true);
        WLUnstable.init_layer_shell("Kickoff-overlay", 1920, 1080, UP | LEFT | RIGHT | DOWN, false);
    
        var size = WLUnstable.get_layer_shell_size();
        print("layer shell size: %i %i\n", size.width, size.height);

        launcher = new AppLauncher(/*  size.width, size.height  */1920, 1080);
    
        WLUnstable.register_on_mouse_down(() => launcher.mouse_down());
        WLUnstable.register_on_mouse_up(() => launcher.mouse_up());
        WLUnstable.register_on_mouse_motion((x,y)=>launcher.mouse_move(x,y)); //fix double
        WLUnstable.register_on_key_down(key=> {
            if(key == 65307){
                WLUnstable.destroy();
                Process.exit (0);
            }
            print("Key %d\n", (int) key);
        });
        
        while (WLUnstable.display_dispatch_blocking() != -1) {
            
            if(launcher.redraw){
                launcher.render();
                WLUnstable.swap_buffers();
                launcher.redraw = false;
            }
        }
    
        WLUnstable.destroy();
        return 0;
    }
}
