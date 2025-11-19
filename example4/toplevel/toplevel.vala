// wlr-foreign-toplevel.vapi
// VAPI bindings for wlr-foreign-toplevel protocol

[CCode (cheader_filename = "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h")]
namespace Zwlr {
    [CCode (cname = "struct zwlr_foreign_toplevel_manager_v1", free_function = "zwlr_foreign_toplevel_manager_v1_destroy")]
    [Compact]
    public class ForeignToplevelManagerV1 {
        [CCode (cname = "zwlr_foreign_toplevel_manager_v1_add_listener")]
        public int add_listener(ForeignToplevelManagerV1Listener listener, void* data);
        
        [CCode (cname = "zwlr_foreign_toplevel_manager_v1_stop")]
        public void stop();
    }
    
    [CCode (cname = "struct zwlr_foreign_toplevel_handle_v1", free_function = "zwlr_foreign_toplevel_handle_v1_destroy")]
    [Compact]
    public class ForeignToplevelHandleV1 {
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_add_listener")]
        public int add_listener(ForeignToplevelHandleV1Listener listener, void* data);
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_set_maximized")]
        public void set_maximized();
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_unset_maximized")]
        public void unset_maximized();
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_set_minimized")]
        public void set_minimized();
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_unset_minimized")]
        public void unset_minimized();
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_activate")]
        public void activate(Wl.Seat seat);
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_close")]
        public void close();
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_set_fullscreen")]
        public void set_fullscreen(Wl.Output? output);
        
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_unset_fullscreen")]
        public void unset_fullscreen();
    }
    
    [CCode (cname = "struct zwlr_foreign_toplevel_manager_v1_listener")]
    public struct ForeignToplevelManagerV1Listener {
        [CCode (delegate_target = false)]
        public ToplevelDelegate toplevel;
        [CCode (delegate_target = false)]
        public FinishedDelegate finished;
    }
    
    [CCode (cname = "struct zwlr_foreign_toplevel_handle_v1_listener")]
    public struct ForeignToplevelHandleV1Listener {
        [CCode (delegate_target = false)]
        public TitleDelegate title;
        [CCode (delegate_target = false)]
        public AppIdDelegate app_id;
        [CCode (delegate_target = false)]
        public OutputEnterDelegate output_enter;
        [CCode (delegate_target = false)]
        public OutputLeaveDelegate output_leave;
        [CCode (delegate_target = false)]
        public StateDelegate state;
        [CCode (delegate_target = false)]
        public DoneDelegate done;
        [CCode (delegate_target = false)]
        public ClosedDelegate closed;
        [CCode (delegate_target = false)]
        public ParentDelegate parent;
    }
    
    [CCode (cname = "zwlr_foreign_toplevel_handle_v1_state")]
    public enum State {
        [CCode (cname = "ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MAXIMIZED")]
        MAXIMIZED,
        [CCode (cname = "ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MINIMIZED")]
        MINIMIZED,
        [CCode (cname = "ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED")]
        ACTIVATED,
        [CCode (cname = "ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_FULLSCREEN")]
        FULLSCREEN
    }
    
    // Delegate types
    [CCode (cname = "void", has_target = false)]
    public delegate void ToplevelDelegate(void* data, ForeignToplevelManagerV1 manager, ForeignToplevelHandleV1 handle);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void FinishedDelegate(void* data, ForeignToplevelManagerV1 manager);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void TitleDelegate(void* data, ForeignToplevelHandleV1 handle, string title);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void AppIdDelegate(void* data, ForeignToplevelHandleV1 handle, string app_id);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void OutputEnterDelegate(void* data, ForeignToplevelHandleV1 handle, Wl.Output output);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void OutputLeaveDelegate(void* data, ForeignToplevelHandleV1 handle, Wl.Output output);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void StateDelegate(void* data, ForeignToplevelHandleV1 handle, Wl.Array array);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void DoneDelegate(void* data, ForeignToplevelHandleV1 handle);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void ClosedDelegate(void* data, ForeignToplevelHandleV1 handle);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void ParentDelegate(void* data, ForeignToplevelHandleV1 handle, ForeignToplevelHandleV1? parent);
}

// Wayland basic types
[CCode (cheader_filename = "wayland-client.h")]
namespace Wl {
    [CCode (cname = "struct wl_display", free_function = "wl_display_disconnect")]
    [Compact]
    public class Display {
        [CCode (cname = "wl_display_dispatch")]
        public int dispatch();
        
        [CCode (cname = "wl_display_roundtrip")]
        public int roundtrip();
        
        [CCode (cname = "wl_display_get_registry")]
        public Registry get_registry();
    }
    
    [CCode (cname = "struct wl_registry", free_function = "wl_registry_destroy")]
    [Compact]
    public class Registry {
        [CCode (cname = "wl_registry_add_listener")]
        public int add_listener(RegistryListener listener, void* data);
        
        [CCode (cname = "wl_registry_bind")]
        public void* bind(uint32 name, void* interface_ptr, uint32 version);
    }
    
    [CCode (cname = "struct wl_registry_listener")]
    public struct RegistryListener {
        [CCode (delegate_target = false)]
        public GlobalDelegate global;
        [CCode (delegate_target = false)]
        public GlobalRemoveDelegate global_remove;
    }
    
    [CCode (cname = "void", has_target = false)]
    public delegate void GlobalDelegate(void* data, Registry registry, uint32 name, string interface_name, uint32 version);
    
    [CCode (cname = "void", has_target = false)]
    public delegate void GlobalRemoveDelegate(void* data, Registry registry, uint32 name);
    
    [CCode (cname = "struct wl_seat")]
    [Compact]
    public class Seat {
    }
    
    [CCode (cname = "struct wl_output")]
    [Compact]
    public class Output {
    }
    
    [CCode (cname = "struct wl_array")]
    public struct Array {
        public size_t size;
        public size_t alloc;
        public void* data;
    }
    
    [CCode (cname = "struct wl_list")]
    public struct List {
        public List* prev;
        public List* next;
        
        [CCode (cname = "wl_list_init")]
        public void init();
        
        [CCode (cname = "wl_list_insert")]
        public void insert(List* elm);
        
        [CCode (cname = "wl_list_remove")]
        public void remove();
        
        [CCode (cname = "wl_list_empty")]
        public bool empty();
    }
    
    [CCode (cname = "struct wl_interface")]
    public struct Interface {
        public unowned string name;
        public int version;
    }
}

// Your custom structures
[CCode (cheader_filename = "toplevel.h")]
namespace Toplevel {
    [CCode (cname = "toplevel_window_t", destroy_function = "", has_type_id = false)]
    public struct Window {
        public Zwlr.ForeignToplevelHandleV1 handle;
        public string app_id;
        public string title;
        public bool activated;
    }
    
    [CCode (cname = "toplevel_created")]
    public void created(Window* window);
    
    [CCode (cname = "toplevel_destroyed")]
    public void destroyed(Window* window);
}