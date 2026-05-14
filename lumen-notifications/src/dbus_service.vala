using GLib;

[DBus(name = "org.freedesktop.Notifications")]
public class NotificationsService : Object {

    private NotificationManager manager;

    public NotificationsService(NotificationManager manager) {
        this.manager = manager;
    }

    public signal void notification_closed(uint32 id, uint32 reason);
    public signal void action_invoked(uint32 id, string action_key);

    [DBus (name = "Notify")]
    public uint32 notify_(string app_name, uint32 replaces_id, string app_icon,
                          string summary, string body, string[] actions,
                          HashTable<string, Variant> hints,
                          int32 expire_timeout) throws DBusError, IOError {
        Urgency urgency = Urgency.NORMAL;
        var u = hints.lookup("urgency");
        if (u != null) {
            if (u.is_of_type(VariantType.BYTE)) {
                urgency = (Urgency) u.get_byte();
            }
        }

        string? image_path = null;
        var ip = hints.lookup("image-path");
        if (ip != null && ip.is_of_type(VariantType.STRING)) {
            image_path = ip.get_string();
        } else {
            var ip2 = hints.lookup("image_path");
            if (ip2 != null && ip2.is_of_type(VariantType.STRING)) {
                image_path = ip2.get_string();
            }
        }

        string? icon = (app_icon != "") ? app_icon : null;
        return manager.submit(replaces_id, app_name, icon, summary, body,
                              actions, urgency, image_path, expire_timeout);
    }

    public void close_notification(uint32 id) throws DBusError, IOError {
        if (manager.has(id)) {
            manager.close(id, REASON_CLOSED);
        }
    }

    public string[] get_capabilities() throws DBusError, IOError {
        return { "body", "body-markup", "actions", "icon-static" };
    }

    public void get_server_information(out string name, out string vendor,
                                       out string version,
                                       out string spec_version)
        throws DBusError, IOError {
        name = "lumen-notifications";
        vendor = "LumenShell";
        version = "0.1";
        spec_version = "1.2";
    }
}
