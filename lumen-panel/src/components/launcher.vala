using Gtk;

#if PANEL_PEEK
public class LauncherButton : Gtk.Button {

    public const int ICON_SIZE = 32;

    public LauncherButton () {
        add_css_class("launcher-button");
        set_size_request(AppEntry.SLOT_WIDTH, AppEntry.SLOT_HEIGHT);
        // Edge-anchored like AppBar so it doesn't drift when the tray grows the row.
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
