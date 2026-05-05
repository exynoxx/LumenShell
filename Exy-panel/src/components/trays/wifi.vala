
/*  # Overall connectivity state
nmcli networking connectivity
# Wi-Fi status
nmcli device status
  */
using Gee;
using GLib;
using DrawKit;

public class WifiTray : IconAndText, IClickable, IUpdateable {

    private class Endpoint {
        public string device;
        public string type;
        public string state;
        public string connection;

        public Endpoint(string device, string type, string state, string connection){
            this.device = device;
            this.type = type;
            this.state = state;
            this.connection = connection;
        }
    }

    public WifiTray(Context ctx) {
        base (ctx, new HoverableIcon("wifi-unknown"), "???");
    }

    public void mouse_down(){

    }
    public void mouse_up(){

    }

    public string get_status()
    {
        return "todo";
    }

    public void update(){
        bool wifi_connected = false;

        var endpoints = get_wifi_endpoints();
        if (endpoints.length == 0){
            return;
        }

        foreach(var endpoint in endpoints){
            if(endpoint.state == "connected"){
                wifi_connected = true;
            }
        }

        var new_icon = (wifi_connected) ? "wifi" : "nowifi";
        
        base.icon.free();
        base.icon.load(new_icon);
    }

    private static Endpoint[] get_wifi_endpoints() {
        var endpoints = new ArrayList<Endpoint>();

        try {
            string stdout;
            string stderr;
            int exit_status;

            Process.spawn_command_line_sync("nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status",
                out stdout,
                out stderr,
                out exit_status
            );

            if (exit_status != 0) {
                warning("nmcli failed: %s", stderr);
                return endpoints.to_array();
            }

            // Format is colon-separated because of -t
            // DEVICE:TYPE:STATE:CONNECTION
            foreach (string line in stdout.strip().split("\n")) {
                string[] parts = line.split(":");
                if (parts.length < 4)
                    continue;

                string device = parts[0];
                string type = parts[1];
                string state = parts[2];
                string connection = parts[3];

                endpoints.add(new Endpoint(device, type, state, connection));
            }
        } catch (Error e) {
            warning("Error running nmcli: %s", e.message);
        }

        return endpoints.to_array();
    }
}