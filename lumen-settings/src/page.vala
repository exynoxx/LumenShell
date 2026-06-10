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

        // Whether build() already manages its own scrolling. When false (the
        // default) the window wraps the page body in a ScrolledWindow. Pages
        // that need fixed (non-scrolling) headers — e.g. a pinned search bar or
        // back button — return true and scroll their content internally.
        public virtual bool scrolls_itself() { return false; }
    }
}
