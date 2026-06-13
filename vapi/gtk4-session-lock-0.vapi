/* gtk4-session-lock-0.vapi — hand-written binding for gtk4-session-lock
 * (https://github.com/wmww/gtk4-session-lock), the sister library to
 * gtk4-layer-shell that turns a Gtk.Window into an ext-session-lock-v1 lock
 * surface. No upstream vapi ships, so we maintain a minimal one (mirrors the
 * shape of /usr/share/vala/vapi/gtk4-layer-shell-0.vapi).
 *
 * Link order: gtk4-session-lock MUST precede gtk4/wayland in the link line,
 * exactly like gtk4-layer-shell, or the protocol hook silently no-ops.
 */
[CCode(cheader_filename = "gtk4-session-lock.h")]
namespace GtkSessionLock {

    // Is the compositor advertising ext-session-lock-v1? Must be checked before
    // attempting to lock.
    [CCode(cname = "gtk_session_lock_is_supported")]
    public bool is_supported();

    // Library ABI version (mirrors gtk_layer_get_*_version helpers).
    [CCode(cname = "gtk_session_lock_get_major_version")]
    public uint get_major_version();
    [CCode(cname = "gtk_session_lock_get_minor_version")]
    public uint get_minor_version();
    [CCode(cname = "gtk_session_lock_get_micro_version")]
    public uint get_micro_version();

    [CCode(cname = "GtkSessionLockInstance", type_id = "gtk_session_lock_instance_get_type ()")]
    public class Instance : GLib.Object {
        [CCode(cname = "gtk_session_lock_instance_new")]
        public Instance();

        // Request the lock. Returns false if the request could not be sent
        // (e.g. already locked by us). The `locked`/`failed` signals report the
        // compositor's verdict asynchronously.
        [CCode(cname = "gtk_session_lock_instance_lock")]
        public bool @lock();

        // Unlock and destroy all lock surfaces. Emits `unlocked`.
        [CCode(cname = "gtk_session_lock_instance_unlock")]
        public void unlock();

        [CCode(cname = "gtk_session_lock_instance_is_locked")]
        public bool is_locked();

        // Each Gtk.Window must be assigned to exactly one Gdk.Monitor before it
        // is presented; the protocol requires one lock surface per output.
        [CCode(cname = "gtk_session_lock_instance_assign_window_to_monitor")]
        public void assign_window_to_monitor(Gtk.Window window, Gdk.Monitor monitor);

        // Compositor accepted the lock — surfaces are now the only thing on
        // screen; safe to show password UI.
        public signal void locked();
        // Compositor rejected the lock (another locker already holds it). The
        // session is NOT secured; bail out.
        public signal void failed();
        // Session unlocked (after unlock(), or the compositor's `finished`).
        public signal void unlocked();
    }
}
