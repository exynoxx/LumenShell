using GLib;

public enum Urgency {
    LOW = 0,
    NORMAL = 1,
    CRITICAL = 2
}

public class Notification : Object {
    public uint32   id;
    public string   app_name;
    public string   app_icon;
    public string   summary;
    public string   body;
    public string[] actions;       // raw [key1, label1, key2, label2, ...]
    public Urgency  urgency = Urgency.NORMAL;
    public string?  image_path = null;
    public int      expire_timeout = -1;

    // Source id of the running expiry timer (0 = none).
    public uint expire_source = 0;

    public Notification(uint32 id) {
        this.id = id;
    }

    public Gdk.RGBA accent_color() {
        switch (urgency) {
            case Urgency.LOW:      return Theme.urgency_low;
            case Urgency.CRITICAL: return Theme.urgency_critical;
            default:               return Theme.urgency_normal;
        }
    }
}
