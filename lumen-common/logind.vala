using GLib;

/**
 * LogindBridge — the single place LumenShell talks to systemd-logind
 * (org.freedesktop.login1). Mirrors the raw-GVariant DBusProxy style of
 * lumen-panel's PowerProfileClient: no typed [DBus] interface, signals handled
 * via the proxy's "g-signal".
 *
 * Responsibilities:
 *   - session control: suspend / reboot / power_off / terminate_session
 *     (all interactive=false; polkit authorizes for the active session, no prompt)
 *   - re-emit Manager.PrepareForSleep as prepare_for_sleep(bool)
 *   - re-emit Session.Lock / Session.Unlock as lock_requested / unlock_requested
 *   - hold a *delay* sleep inhibitor so a locker can map before the kernel
 *     freezes the machine (release_delay_inhibitor lets sleep proceed)
 *
 * Fail-soft throughout: if the system bus or login1 is unavailable every method
 * is a no-op (warn-and-return), matching the repo's swallow-and-warn convention.
 */
public class LogindBridge : GLib.Object {

    public signal void prepare_for_sleep(bool starting);
    public signal void lock_requested();
    public signal void unlock_requested();

    const string SERVICE      = "org.freedesktop.login1";
    const string MGR_PATH     = "/org/freedesktop/login1";
    const string MGR_IFACE    = "org.freedesktop.login1.Manager";
    const string SESSION_IFACE = "org.freedesktop.login1.Session";

    DBusProxy?  manager = null;
    DBusProxy?  session = null;
    string      session_id   = "";
    string      session_path = "";
    int         inhibit_fd   = -1;

    public LogindBridge() {
        try {
            manager = new DBusProxy.for_bus_sync(
                BusType.SYSTEM, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, null,
                SERVICE, MGR_PATH, MGR_IFACE, null);
        } catch (Error e) {
            warning("logind: cannot reach login1.Manager: %s", e.message);
            manager = null;
            return;
        }

        manager.g_signal.connect((sender, signal_name, parameters) => {
            if (signal_name == "PrepareForSleep") {
                bool starting = false;
                parameters.get("(b)", out starting);
                prepare_for_sleep(starting);
            }
        });

        resolve_session();
        take_delay_inhibitor();
    }

    void resolve_session() {
        if (manager == null) return;
        try {
            var env_id = Environment.get_variable("XDG_SESSION_ID");
            if (env_id != null && env_id != "") {
                session_id = env_id;
                var r = manager.call_sync("GetSession",
                    new Variant("(s)", env_id), DBusCallFlags.NONE, 2000, null);
                r.get("(o)", out session_path);
            } else {
                var r = manager.call_sync("GetSessionByPID",
                    new Variant("(u)", (uint) Posix.getpid()),
                    DBusCallFlags.NONE, 2000, null);
                r.get("(o)", out session_path);
            }
        } catch (Error e) {
            warning("logind: resolve session: %s", e.message);
            return;
        }
        if (session_path == "") return;

        try {
            session = new DBusProxy.for_bus_sync(
                BusType.SYSTEM, DBusProxyFlags.NONE, null,
                SERVICE, session_path, SESSION_IFACE, null);
            if (session_id == "") {
                var idv = session.get_cached_property("Id");
                if (idv != null && idv.is_of_type(VariantType.STRING))
                    session_id = idv.get_string();
            }
            session.g_signal.connect((sender, signal_name, parameters) => {
                if (signal_name == "Lock")   lock_requested();
                if (signal_name == "Unlock") unlock_requested();
            });
        } catch (Error e) {
            warning("logind: session proxy: %s", e.message);
        }
    }

    // ---- delay inhibitor ----------------------------------------------------

    public void take_delay_inhibitor() {
        if (manager == null || inhibit_fd >= 0) return;
        try {
            UnixFDList out_fds;
            var ret = manager.call_with_unix_fd_list_sync(
                "Inhibit",
                new Variant("(ssss)", "sleep", "LumenShell",
                            "Lock screen before sleep", "delay"),
                DBusCallFlags.NONE, 2000, null, out out_fds, null);
            int handle = 0;
            ret.get("(h)", out handle);
            inhibit_fd = out_fds.get(handle);
        } catch (Error e) {
            warning("logind: take inhibitor: %s", e.message);
            inhibit_fd = -1;
        }
    }

    public void release_delay_inhibitor() {
        if (inhibit_fd >= 0) {
            Posix.close(inhibit_fd);
            inhibit_fd = -1;
        }
    }

    // ---- session control ----------------------------------------------------

    public async void suspend()   { yield call_manager("Suspend"); }
    public async void reboot()    { yield call_manager("Reboot"); }
    public async void power_off() { yield call_manager("PowerOff"); }

    async void call_manager(string method) {
        if (manager == null) return;
        try {
            yield manager.call(method, new Variant("(b)", false),
                               DBusCallFlags.NONE, 5000, null);
        } catch (Error e) {
            warning("logind: %s: %s", method, e.message);
        }
    }

    public async void terminate_session() {
        if (manager == null) return;
        if (session_id == "") {
            // No id resolved — fall back to ending the seat gracefully is not
            // possible; warn and bail rather than killing the compositor.
            warning("logind: no session id; cannot TerminateSession");
            return;
        }
        try {
            yield manager.call("TerminateSession", new Variant("(s)", session_id),
                               DBusCallFlags.NONE, 5000, null);
        } catch (Error e) {
            warning("logind: TerminateSession: %s", e.message);
        }
    }
}
