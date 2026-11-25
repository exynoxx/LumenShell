// Known tray applets; lumen-panel drops ids not listed here and appends new
// ones on upgrade, lumen-settings builds its reorder list from it.
namespace LumenTray {
    public struct AppletInfo { public string id; public string label; }

    // Canonical default order.
#if FREEBSD
    // No BlueZ on FreeBSD (its netgraph Bluetooth stack has no DBus API), so
    // no Bluetooth applet; see BluetoothService.supported.
    public const AppletInfo[] CATALOG = {
        { "systray",   "System tray" },
        { "search",    "Search" },
        { "wifi",      "Wi-Fi" },
        { "battery",   "Battery" },
        { "sound",     "Sound" },
        { "clock",     "Clock" },
        { "exit",      "Power / session" },
    };
#else
    public const AppletInfo[] CATALOG = {
        { "systray",   "System tray" },
        { "search",    "Search" },
        { "wifi",      "Wi-Fi" },
        { "bluetooth", "Bluetooth" },
        { "battery",   "Battery" },
        { "sound",     "Sound" },
        { "clock",     "Clock" },
        { "exit",      "Power / session" },
    };
#endif
}
