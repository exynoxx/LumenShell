using Gtk;

namespace LumenSettings {

    public interface SettingsPage : GLib.Object {
        public abstract string id          { owned get; }
        public abstract string title       { owned get; }
        public abstract string icon_name   { owned get; }
        public abstract Gtk.Widget build();

        // Binary the Restart button kills and respawns, or null for none.
        public virtual string? restart_target() { return null; }
    }
}
