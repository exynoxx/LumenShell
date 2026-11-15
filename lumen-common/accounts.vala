using GLib;

public class AccountsClient : GLib.Object {

    public struct UserInfo {
        public string real_name;   // "" when unknown
        public string icon_path;   // "" when none resolvable
    }

    const string SERVICE   = "org.freedesktop.Accounts";
    const string ACC_PATH  = "/org/freedesktop/Accounts";
    const string ACC_IFACE = "org.freedesktop.Accounts";
    const string USR_IFACE = "org.freedesktop.Accounts.User";

    // "" if Accounts is unavailable.
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

    // Memoized: the lookup blocks on the system bus and must stay off the
    // lock critical path (lumen-lockscreen warms it at startup).
    static UserInfo? cached = null;

    // Avatar: AccountsService IconFile → ~/.face → "".
    public static UserInfo load_current_user() {
        if (cached != null)
            return cached;

        var info = UserInfo() {
            real_name = "",
            icon_path = "",
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

    // Live (uncached) user record with properties loaded; null if Accounts
    // is unavailable. lumen-settings reads AccountType / Language from it.
    public static DBusProxy? current_user_proxy() {
        var path = current_user_path();
        if (path == "") return null;
        try {
            return new DBusProxy.for_bus_sync(
                BusType.SYSTEM, DBusProxyFlags.NONE, null,
                SERVICE, path, USR_IFACE, null);
        } catch (Error e) {
            warning("accounts: user proxy: %s", e.message);
            return null;
        }
    }

    // Own-user writes (polkit change-own-user-data: no prompt for the
    // active local session). Throw so the caller can show the failure.
    public static void set_real_name(string name) throws Error  { call_user("SetRealName", name); }
    public static void set_icon_file(string path) throws Error  { call_user("SetIconFile", path); }
    public static void set_language(string locale) throws Error { call_user("SetLanguage", locale); }

    static void call_user(string method, string arg) throws Error {
        var path = current_user_path();
        if (path == "") throw new IOError.NOT_FOUND("AccountsService is unavailable");
        var usr = new DBusProxy.for_bus_sync(
            BusType.SYSTEM, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, null,
            SERVICE, path, USR_IFACE, null);
        usr.call_sync(method, new Variant("(s)", arg), DBusCallFlags.NONE, 5000, null);
        cached = null;   // load_current_user() must see the new value
    }

    // So login managers preselect this session next time. polkit allows
    // own-user writes for the active local session without a prompt.
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
