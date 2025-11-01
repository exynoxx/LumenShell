[CCode (cname = "zwlr_layer_shell_v1", has_type_id=false)]
public struct LayerShellV1 {}

[CCode (cname = "zwlr_layer_surface_v1", has_type_id=false)]
public struct LayerSurfaceV1 {}

[CCode (cname = "zwlr_layer_shell_v1_get_layer_surface")]
public extern LayerSurfaceV1 layer_shell_get_layer_surface(
    LayerShellV1 layer_shell,
    IntPtr surface,
    IntPtr output,
    uint layer,
    string namespace_);

[CCode (cname = "zwlr_layer_surface_v1_set_anchor")]
public extern void layer_surface_set_anchor(LayerSurfaceV1 surface, uint anchor);

[CCode (cname = "zwlr_layer_surface_v1_set_size")]
public extern void layer_surface_set_size(LayerSurfaceV1 surface, uint width, uint height);

[CCode (cname = "zwlr_layer_surface_v1_set_exclusive_zone")]
public extern void layer_surface_set_exclusive_zone(LayerSurfaceV1 surface, int32 exclusive_zone);

[CCode (cname = "zwlr_layer_surface_v1_add_listener")]
public extern void layer_surface_add_listener(LayerSurfaceV1 surface, IntPtr listener, IntPtr data);
