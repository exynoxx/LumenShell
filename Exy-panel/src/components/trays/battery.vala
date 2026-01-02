
/*  /sys/class/power_supply/BAT0/
capacity → battery percentage (0–100)

status → Charging, Discharging, Full

voltage_now, current_now → detailed info  */

public class BatteryTray : TrayIcon {

    public BatteryTray() {
        base ("nobattery");
        status();
    }

    public override void mouse_down(){
    }
    public override void mouse_up(){

    }

    private async void status(){
        var status = exec("cat /sys/class/power_supply/BAT0/status");

        var new_icon = "nobattery";
        if(status == "discharging" || status.contains("full")){

            var full = exec_int("cat /sys/class/power_supply/BAT0/charge_full");
            var current = exec_int("cat /sys/class/power_supply/BAT0/charge_now");

            var percent = (current/(float)full)*100;
            print("Battery: %f\n", percent);

            if(percent >= 70) 
                new_icon = "high";
            else if(percent < 30)
                new_icon = "low";
            else
                new_icon = "mid";

        } else if (status == "charging"){
            new_icon = "charging";
        } else {
            print("battery: status unknown: >%s<\n", status);
            return;
        }

        free();
        base.load(new_icon);
    }

    private static int exec_int(string cmd){
        var result = exec(cmd);
        return int.parse(result);
    }

    private static string exec(string cmd) {
        string stdout;
        string stderr;

        try {
            int exit_status;

            Process.spawn_command_line_sync(cmd,
                out stdout,
                out stderr,
                out exit_status
            );

            if (exit_status != 0) {
                warning("cat failed: %s", stderr);
                return stderr;
            }

            return stdout.strip().ascii_down();
        } catch (Error e) {
            warning("Exception running cat: %s", e.message);
            return "";
        }
    }
}
