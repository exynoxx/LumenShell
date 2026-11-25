using GLib;

// Session/power bridge. Talks to systemd-logind (org.freedesktop.login1) and,
// where logind isn't running — FreeBSD, and other non-systemd systems —
// to ConsoleKit2 (org.freedesktop.ConsoleKit), which exposes the same
// Manager methods (Inhibit, Suspend, Reboot, PowerOff, PrepareForSleep) and
// Session Lock/Unlock signals under different names.
// Fail-soft: with neither, power actions fall back to the native tools
// (FreeBSD: zzz(8) and shutdown(8), usable by the `operator` group) and
// everything else is a warn-and-return no-op.
public class LogindBridge : GLib.Object {

    public signal void prepare_for_sleep(bool starting);
    public signal void lock_requested();
    public signal void unlock_requested();

    const string SERVICE      = "org.freedesktop.login1";
    const string MGR_PATH     = "/org/freedesktop/login1";
    const string MGR_IFACE    = "org.freedesktop.login1.Manager";
    const string SESSION_IFACE = "org.freedesktop.login1.Session";

    const string CK_SERVICE       = "org.freedesktop.ConsoleKit";
    const string CK_MGR_PATH      = "/org/freedesktop/ConsoleKit/Manager";
    const string CK_MGR_IFACE     = "org.freedesktop.ConsoleKit.Manager";
    const string CK_SESSION_IFACE = "org.freedesktop.ConsoleKit.Session";

    DBusProxy?  manager = null;
    DBusProxy?  session = null;
    bool        consolekit   = false;
    string      session_id   = "";
    string      session_path = "";
    int         inhibit_fd   = -1;
    int         idle_fd      = -1;

    public LogindBridge(bool sleep_inhibitor = true) {
        var login1 = make_proxy(SERVICE, MGR_PATH, MGR_IFACE);
        if (login1 != null && login1.get_name_owner() != null) {
            manager = login1;
        } else {
            var ck = make_proxy(CK_SERVICE, CK_MGR_PATH, CK_MGR_IFACE);
            if (ck != null && activate(ck)) {
                manager = ck;
                consolekit = true;
            } else {
                // As before: login1 may yet be bus-activated, and a failed
                // power call still falls back to native_power().
                manager = login1;
            }
        }
        if (manager == null) {
            warning("logind: cannot reach login1 or ConsoleKit2");
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
        if (sleep_inhibitor) take_delay_inhibitor();
    }

    // The bus name, path and interface of the Manager that is live, so other
    // code (lumen-lockscreen's clock) can subscribe to the same PrepareForSleep.
    public static void sleep_signal_source(out string service, out string path,
                                           out string iface) {
        service = SERVICE; path = MGR_PATH; iface = MGR_IFACE;
        if (has_owner(SERVICE)) return;
        if (has_owner(CK_SERVICE)) {
            service = CK_SERVICE; path = CK_MGR_PATH; iface = CK_MGR_IFACE;
        }
    }

    static bool has_owner(string name) {
        try {
            var bus = Bus.get_sync(BusType.SYSTEM);
            var r = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "NameHasOwner", new Variant("(s)", name),
                new VariantType("(b)"), DBusCallFlags.NONE, 2000, null);
            bool owned = false;
            r.get("(b)", out owned);
            return owned;
        } catch (Error e) {
            return false;
        }
    }

    static DBusProxy? make_proxy(string service, string path, string iface) {
        try {
            return new DBusProxy.for_bus_sync(
                BusType.SYSTEM, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, null,
                service, path, iface, null);
        } catch (Error e) {
            warning("logind: cannot reach %s: %s", service, e.message);
            return null;
        }
    }

    // A proxy to an absent name constructs fine and then fails every call, so
    // only an owned (or successfully bus-activated) name counts.
    static bool activate(DBusProxy p) {
        if (p.get_name_owner() != null) return true;
        try {
            p.call_sync("org.freedesktop.DBus.Peer.Ping", null,
                        DBusCallFlags.NONE, 3000, null);
            return true;
        } catch (Error e) {
            return false;
        }
    }

    void resolve_session() {
        if (manager == null) return;
        if (consolekit) { resolve_ck_session(); return; }
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

    // ConsoleKit2: the session owning our pid; its id is the object path's
    // last element (e.g. Session2), which is what XDG_SESSION_ID holds too.
    void resolve_ck_session() {
        try {
            var r = manager.call_sync("GetSessionForUnixProcess",
                new Variant("(u)", (uint) Posix.getpid()),
                DBusCallFlags.NONE, 2000, null);
            r.get("(o)", out session_path);
        } catch (Error e) {
            try {
                var r = manager.call_sync("GetCurrentSession", null,
                    DBusCallFlags.NONE, 2000, null);
                r.get("(o)", out session_path);
            } catch (Error e2) {
                warning("logind: ConsoleKit2 resolve session: %s", e2.message);
                return;
            }
        }
        if (session_path == "") return;
        session_id = Path.get_basename(session_path);
        try {
            session = new DBusProxy.for_bus_sync(
                BusType.SYSTEM, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, null,
                CK_SERVICE, session_path, CK_SESSION_IFACE, null);
            session.g_signal.connect((sender, signal_name, parameters) => {
                if (signal_name == "Lock")   lock_requested();
                if (signal_name == "Unlock") unlock_requested();
            });
        } catch (Error e) {
            warning("logind: ConsoleKit2 session proxy: %s", e.message);
        }
    }

    // Delay (not block) so a locker can map before sleep; release to let it proceed.
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

    // Blocks logind's IdleAction only; manual suspend and the lid switch are
    // deliberately left alone.
    public void set_idle_inhibited(bool on) {
        if (!on) {
            if (idle_fd >= 0) { Posix.close(idle_fd); idle_fd = -1; }
            return;
        }
        if (manager == null || idle_fd >= 0) return;
        try {
            UnixFDList out_fds;
            var ret = manager.call_with_unix_fd_list_sync(
                "Inhibit",
                new Variant("(ssss)", "idle", "LumenShell", "Caffeine", "block"),
                DBusCallFlags.NONE, 2000, null, out out_fds, null);
            int handle = 0;
            ret.get("(h)", out handle);
            idle_fd = out_fds.get(handle);
        } catch (Error e) {
            warning("logind: take idle inhibitor: %s", e.message);
            idle_fd = -1;
        }
    }

    public void release_delay_inhibitor() {
        if (inhibit_fd >= 0) {
            Posix.close(inhibit_fd);
            inhibit_fd = -1;
        }
    }

    // interactive=false: polkit allows these for the active session, no prompt.
    public async void suspend()   { yield call_manager("Suspend"); }
    public async void reboot()    { yield call_manager("Reboot"); }
    public async void power_off() { yield call_manager("PowerOff"); }

    async void call_manager(string method) {
        if (manager == null) { native_power(method); return; }
        try {
            yield manager.call(method, new Variant("(b)", false),
                               DBusCallFlags.NONE, 5000, null);
        } catch (Error e) {
            warning("logind: %s: %s", method, e.message);
            native_power(method);
        }
    }

    // No session manager (or it refused): the system's own tools. On FreeBSD
    // shutdown(8) is executable by the `operator` group and zzz(8) needs
    // /dev/acpi, which that group can also write.
    static void native_power(string method) {
#if FREEBSD
        switch (method) {
            case "Suspend":  LumenCommon.Proc.spawn_detached({ "zzz" }); break;
            case "Reboot":   LumenCommon.Proc.spawn_detached({ "shutdown", "-r", "now" }); break;
            case "PowerOff": LumenCommon.Proc.spawn_detached({ "shutdown", "-p", "now" }); break;
        }
#endif
    }

    public async void terminate_session() {
        if (manager == null || consolekit) {
            // ConsoleKit2 has no TerminateSession: ending the compositor ends
            // the session it started.
            end_compositor();
            return;
        }
        if (session_id == "") {
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

    // Last resort for logout: SIGTERM our own Wayfire.
    static void end_compositor() {
#if FREEBSD
        LumenCommon.Proc.spawn_detached({
            "pkill", "-TERM", "-U", "%u".printf((uint) Posix.getuid()), "-x", "wayfire"
        });
#else
        warning("logind: no session manager; cannot log out");
#endif
    }
}
