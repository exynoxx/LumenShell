using DrawKit;
using WLHooks;
using GLES2;

namespace Main {

    public static bool redraw = true;
    public static void queue_redraw(){
        redraw = true;
    }

    private static Processor processor;
    public static AnimationManager animations;
    public static KeyboardManager keyboardMngr;
    
    static int main(string[] args) {
    
        WLHooks.grab_keyboard(true);
        WLHooks.init();

        var size = WLHooks.get_screen_size();
        print("WLHooks - screen size: %i %i\n", size.width, size.height);
        
        keyboardMngr = new KeyboardManager();
        animations = new AnimationManager();
        processor = new Processor(size.width, size.height);

        WLHooks.register_on_mouse_down(processor.mouse_down);
        WLHooks.register_on_mouse_up(processor.mouse_up);
        WLHooks.register_on_mouse_motion(processor.mouse_move); //fix double
        WLHooks.register_on_key_down(keyboardMngr.key_down);
        WLHooks.register_on_key_up(keyboardMngr.key_up);

        //wlhooks -> keybordMngdr -> processor -> ...
        keyboardMngr.on_key_down = processor.key_down;
        //keyboardMngr.on_key_up = processor.key_up;
        
        while (WLHooks.display_dispatch_blocking() != -1) {
            if(keyboardMngr.key_is_down){
                keyboardMngr.main_loop();
            }
            if(redraw || animations.has_active){
                animations.update();
                processor.render();
                WLHooks.swap_buffers();
                redraw = false;
            }
        }
    
        WLHooks.destroy();
        return 0;
    }
}
