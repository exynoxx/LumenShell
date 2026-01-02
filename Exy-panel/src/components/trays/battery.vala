
/*  /sys/class/power_supply/BAT0/
capacity → battery percentage (0–100)

status → Charging, Discharging, Full

voltage_now, current_now → detailed info  */

public class BatteryTray : TrayIcon {

    public BatteryTray() {
        base ("mid");
    }

    public override void mouse_down(){
    }
    public override void mouse_up(){

    }
}
