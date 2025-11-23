using Toplevel;

/*  [CCode (cheader_filename = "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h")]
namespace Zwlr {
    [CCode (cname = "struct zwlr_foreign_toplevel_handle_v1", free_function = "zwlr_foreign_toplevel_handle_v1_destroy")]
    [Compact]
    public class ForeignToplevelHandleV1 {
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_set_minimized")]
        public extern void set_minimized();
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_unset_minimized")]
        public extern void unset_minimized();
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_activate")]
        public void activate(Wl.Seat seat);
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_close")]
        public extern void close();
    }
}  */

[CCode (cheader_filename = "toplevel.h")]
namespace Toplevel {
    [CCode (cname = "toplevel_window_t", destroy_function = "", has_type_id = false)]
    public class Window {
        //public unowned Zwlr.ForeignToplevelHandleV1 handle;
        public string app_id;
        public string title;
        public bool activated;
    }

    
}

public interface ITopLevelManager {

    [CCode (cname = "toplevel_created")]
    public abstract void Toplevel_created(Toplevel.Window *window);

    [CCode (cname = "toplevel_destroyed")]
    public abstract void Toplevel_destroyed(Toplevel.Window *window);

    [CCode (cname = "toplevel_focused")]
    public abstract void toplevel_focused(Toplevel.Window *window);
}

public class TopLevelManager : ITopLevelManager{
    
    [CCode (cname = "toplevel_init")]
    public extern void init(Gdk.Display display);

    [CCode (cname = "toplevel_created")]
    public void Toplevel_created(Toplevel.Window *window){
        print("Toplevel_created");
    }

    [CCode (cname = "toplevel_destroyed")]
    public void Toplevel_destroyed(Toplevel.Window *window){
        print("Toplevel_destroyed");

    }

    [CCode (cname = "toplevel_focused")]
    public void toplevel_focused(Toplevel.Window *window){
        print("Toplevel_focused");
    }
}