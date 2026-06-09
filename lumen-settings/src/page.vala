using Gtk;

namespace LumenSettings {

    public interface SettingsPage : GLib.Object {
        public abstract string id          { owned get; }
        public abstract string title       { owned get; }
        public abstract string icon_name   { owned get; }
        public abstract Gtk.Widget build();

        // Executable to relaunch when the header's Restart button is pressed,
        // or null for pages that have nothing to restart. The window kills the
        // running process and respawns it so config changes take effect.
        public virtual string? restart_target() { return null; }
    }
}
