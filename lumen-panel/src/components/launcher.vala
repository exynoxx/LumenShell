using Gtk;

// A persistent ChromeOS-style launcher button pinned to the left edge of the
// panel. Clicking it toggles the app-drawer reveal (whichever of curtain-peek /
// slide-peek is loaded). Compiled only in a PANEL_PEEK build, since without the
// peek IPC the button has nothing to do.
#if PANEL_PEEK
public class LauncherButton : Gtk.Button {

    public const int ICON_SIZE = 32;

    public LauncherButton () {
        add_css_class("launcher-button");
        set_size_request(AppEntry.SLOT_WIDTH, AppEntry.SLOT_HEIGHT);
        // Anchor to the panel edge like the AppBar does, so the button stays
        // put against the bottom (or top) strip instead of re-centering — and
        // drifting — when the tray expands and grows the row's height.
        valign = PanelConfig.at_top ? Gtk.Align.START : Gtk.Align.END;
        tooltip_text = "Apps";

        var image = new Gtk.Image() {
            pixel_size = ICON_SIZE,
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
        };
        image.set_from_resource("/dev/lumen/panel/icons/app.svg");
        set_child(image);

        clicked.connect(() => PeekIpc.app_drawer());
    }
}
#endif
