using GLib;

/**
 * AccountsClient — the single place LumenShell reads (and writes) the current
 * user's AccountsService record (org.freedesktop.Accounts). Mirrors the
 * raw-DBusProxy style of lumen-common/logind.vala: no typed [DBus] interface,
 * synchronous calls, fail-soft everywhere.
 *
 * Two consumers today:
 *   - lumen-lockscreen: avatar + real name on the lock card (load_current_user).
 *   - lumen-session: stamps the chosen session back onto the user record at
 *     login (set_current_session) so a Wayland login manager preselects
 *     LumenShell next time — the job the (junked) greeter would otherwise own.
 *
 * Source-included into each consumer (no shared .so), same convention as
 * logind.vala / display_profiles.vala.
 */
public class AccountsClient : GLib.Object {

    public struct UserInfo {
        public string real_name;   // "" when unknown
        public string icon_path;   // "" when none resolvable
        public string xsession;    // "" when unset
    }

    const string SERVICE   = "org.freedesktop.Accounts";
    const string ACC_PATH  = "/org/freedesktop/Accounts";
    const string ACC_IFACE = "org.freedesktop.Accounts";
    const string USR_IFACE = "org.freedesktop.Accounts.User";

    // Resolve the object path of the current user's AccountsService record.
    // Returns "" (and warns) if Accounts is unavailable.
    static string current_user_path() {
        var name = Environment.get_user_name();
        try {
            var acc = new DBusProxy.for_bus_sync(
                BusType.SYSTEM, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, null,
                SERVICE, ACC_PATH, ACC_IFACE, null);
            var r = acc.call_sync("FindUserByName", new Variant("(s)", name),
                                  DBusCallFlags.NONE, 2000, null);
            string path = "";
            r.get("(o)", out path);
            return path;
        } catch (Error e) {
            warning("accounts: FindUserByName(%s): %s", name, e.message);
            return "";
        }
    }

    // The current user's identity never changes during a session, so the
    // (system-bus-blocking) lookup is memoized after the first call. This keeps
    // it off the lock critical path: lumen-lockscreen warms it once at startup
    // and every subsequent make_window() reads the cache. See load_current_user.
    static UserInfo? cached = null;

    // Synchronous, fail-soft. Fallback chain for the avatar:
    // AccountsService IconFile → ~/.face → "". Result is memoized.
    public static UserInfo load_current_user() {
        if (cached != null)
            return cached;

        var info = UserInfo() {
            real_name = "",
            icon_path = "",
            xsession  = "",
        };

        var path = current_user_path();
        if (path != "") {
            try {
                var usr = new DBusProxy.for_bus_sync(
                    BusType.SYSTEM, DBusProxyFlags.NONE, null,
                    SERVICE, path, USR_IFACE, null);
                var rn = usr.get_cached_property("RealName");
                if (rn != null && rn.is_of_type(VariantType.STRING))
                    info.real_name = rn.get_string();
                var ic = usr.get_cached_property("IconFile");
                if (ic != null && ic.is_of_type(VariantType.STRING))
                    info.icon_path = ic.get_string();
                var xs = usr.get_cached_property("XSession");
                if (xs != null && xs.is_of_type(VariantType.STRING))
                    info.xsession = xs.get_string();
            } catch (Error e) {
                warning("accounts: read user record: %s", e.message);
            }
        }

        if (info.icon_path == "" || !FileUtils.test(info.icon_path, FileTest.EXISTS)) {
            var face = Environment.get_home_dir() + "/.face";
            info.icon_path = FileUtils.test(face, FileTest.EXISTS) ? face : "";
        }
        if (info.real_name == "")
            info.real_name = Environment.get_real_name();   // GECOS, else "Unknown"

        cached = info;
        return info;
    }

    // Stamp the chosen session id onto the user record so login managers
    // preselect it next time. Both setters are own-user-data writes (polkit
    // allows them for the active local session — no prompt). Fail-soft.
    public static void set_current_session(string session_id) {
        if (session_id == "") return;
        var path = current_user_path();
        if (path == "") return;
        try {
            var usr = new DBusProxy.for_bus_sync(
                BusType.SYSTEM, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, null,
                SERVICE, path, USR_IFACE, null);
            usr.call_sync("SetXSession", new Variant("(s)", session_id),
                          DBusCallFlags.NONE, 2000, null);
            usr.call_sync("SetSession", new Variant("(s)", session_id),
                          DBusCallFlags.NONE, 2000, null);
        } catch (Error e) {
            warning("accounts: set session '%s': %s", session_id, e.message);
        }
    }
}
