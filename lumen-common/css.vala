// The one CSS-provider install every GTK app does. Needs gtk4 only.
namespace LumenCommon.Css {
    public void install(string css) {
        var p = new Gtk.CssProvider();
        p.load_from_string(css);
        Gtk.StyleContext.add_provider_for_display((!) Gdk.Display.get_default(), p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    // `prefix` (usually @define-color lines) goes first so the stylesheet can use it.
    public void install_resource(string resource, string prefix = "") {
        try {
            var bytes = resources_lookup_data(resource, ResourceLookupFlags.NONE);
            install(prefix + "\n" + (string) bytes.get_data());
        } catch (Error e) {
            warning("failed to load %s: %s", resource, e.message);
        }
    }
}
