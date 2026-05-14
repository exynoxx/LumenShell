[CCode (cheader_filename = "toplevel_shim.h", cprefix = "toplevel_shim_", lower_case_cprefix = "toplevel_shim_")]
namespace ToplevelShim {

    [CCode (cname = "toplevel_entry", has_type_id = false)]
    public struct Entry {
        public uint32 id;
        public unowned string? app_id;
        public unowned string? title;
        public bool   activated;
        public void*  handle;
    }

    [CCode (cname = "toplevel_added_cb",   has_target = false)]
    public delegate void AddedCb   (Entry *e, void *user);
    [CCode (cname = "toplevel_changed_cb", has_target = false)]
    public delegate void ChangedCb (Entry *e, void *user);
    [CCode (cname = "toplevel_closed_cb",  has_target = false)]
    public delegate void ClosedCb  (uint32 id, void *user);

    [CCode (cname = "toplevel_shim_init")]
    public int init (Wl.Display display, AddedCb added, ChangedCb changed, ClosedCb closed, void *user);

    [CCode (cname = "toplevel_shim_finish_setup")]
    public void finish_setup (Wl.Display display);

    [CCode (cname = "toplevel_shim_destroy")]
    public void destroy ();
}
