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

        var socket_path = SystemUtils.get_socket_path ("kickoff.sock");
        var socket = new SocketUtils (socket_path);

        if (socket.bind_socket ()) {
            print ("No existing instance, running as main\n");

            socket.listen_forever ((cmd) => {
                switch (cmd) {
                    case "show":
                        launcher.show ();
                        break;
                }
            });
        } else {
            print ("Existing instance detected, sending command\n");
            socket.send_command ("show");
            return 0;
        }
    
        WLHooks.grab_keyboard(true);
        WLHooks.init();

        var size = WLHooks.get_screen_size();
        print("WLHooks - screen size: %i %i\n", size.width, size.height);
        
        animations = new AnimationManager();
        launcher = new AppLauncher(size.width, size.height);

        WLHooks.register_on_mouse_down(launcher.mouse_down);
        WLHooks.register_on_mouse_up(launcher.mouse_up);
        WLHooks.register_on_mouse_motion(launcher.mouse_move); //fix double
        WLHooks.register_on_key_up(key=> {
            if(key == 65307){
                WLHooks.destroy();
                Process.exit (0);
            }

            if(key == 97){
                WLHooks.destroy_layer_shell();
            }

            launcher.key_up(key);
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
