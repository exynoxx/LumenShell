// Shared catalog of known lumen-panel tray applets. Single source of truth for
// both binaries: lumen-panel uses it for the default order + the known-id set
// (so unknown/stale ids in panel.json are dropped, and new built-ins are
// appended on upgrade), and lumen-settings uses it to build the reorder list.
// Compiled into both — see meson.build (tray_catalog_source).
namespace LumenTray {
    public struct AppletInfo { public string id; public string label; }

    // Canonical order + labels. Editing this list (adding a built-in applet)
    // updates both the panel's upgrade-safe append order and the settings UI.
    public const AppletInfo[] CATALOG = {
        { "systray",   "System tray" },
        { "wifi",      "Wi-Fi" },
        { "bluetooth", "Bluetooth" },
        { "battery",   "Battery" },
        { "sound",     "Sound" },
        { "clock",     "Clock" },
        { "exit",      "Power / session" },
    };
}
