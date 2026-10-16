using Gtk;

public class WifiModule : GLib.Object {

    WifiService service;
    CcToggleRow row;

    public WifiModule (WifiService service) {
        this.service = service;
        row = new CcToggleRow ("Wi-Fi", "wifi", "nowifi", true);   // compact: sits beside Bluetooth
        row.toggled.connect ((want) => service.set_radio (want));
        service.state_changed.connect (update);
        update ();
    }

    public CcToggleRow tile () { return row; }

    void update () {
        row.set_on (service.enabled);
        string sub;
        if (!service.enabled)                                       sub = "Off";
        else if (service.connected_ssid != "" && service.connected_ssid != "--")
                                                                    sub = service.connected_ssid;
        else if (service.ethernet_connected)                        sub = "Ethernet";
        else                                                        sub = "On";
        row.set_subtitle (sub);
    }
}
