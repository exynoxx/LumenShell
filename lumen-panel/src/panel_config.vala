using GLib;

// Global panel placement, read once at startup from panel.ini. Widgets that
// must mirror their layout when the panel sits at the top of the screen
// (popover direction, tray growth, the backdrop strip's edge) consult
// PanelConfig.at_top rather than threading the flag through every constructor.
public class PanelConfig {
    public static bool at_top = false;

    public static void load () {
        var ini = Environment.get_user_config_dir() + "/lumen-shell/panel.ini";
        at_top = Ini.get_key_value(ini, "position") == "top";
    }
}
