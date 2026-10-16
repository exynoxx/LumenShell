// Known tray applets; lumen-panel drops ids not listed here and appends new
// ones on upgrade, lumen-settings builds its reorder list from it.
namespace LumenTray {
    public struct AppletInfo { public string id; public string label; }

    // Canonical default order.
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
