/* Hand-maintained: gtk4-session-lock ships no upstream vapi.
 * Link order: it MUST precede gtk4/wayland, or the protocol hook silently no-ops. */
[CCode(cheader_filename = "gtk4-session-lock.h")]
namespace GtkSessionLock {

    // Must be checked before attempting to lock.
    [CCode(cname = "gtk_session_lock_is_supported")]
    public bool is_supported();

    [CCode(cname = "GtkSessionLockInstance", type_id = "gtk_session_lock_instance_get_type ()")]
    public class Instance : GLib.Object {
        [CCode(cname = "gtk_session_lock_instance_new")]
        public Instance();

        // false if the request could not be sent; the verdict arrives via
        // `locked`/`failed`.
        [CCode(cname = "gtk_session_lock_instance_lock")]
        public bool @lock();

        // Destroys all lock surfaces.
        [CCode(cname = "gtk_session_lock_instance_unlock")]
        public void unlock();

        // Each Gtk.Window must be assigned to exactly one Gdk.Monitor before it
        // is presented; the protocol requires one lock surface per output.
        [CCode(cname = "gtk_session_lock_instance_assign_window_to_monitor")]
        public void assign_window_to_monitor(Gtk.Window window, Gdk.Monitor monitor);

        public signal void locked();
        // Another locker holds the lock; the session is NOT secured.
        public signal void failed();
        // Also fires on the compositor's `finished`.
        public signal void unlocked();
    }
}
