using GLib;

// lumen-lockctl — thin CLI mirror of lumen-osdctl. Sends DBus calls to the
// lumen-lockscreen daemon. Does NOT auto-spawn it: prints an error and exits
// non-zero if org.lumenshell.Lock has no owner.

private const string USAGE =
"""Usage: lumen-lockctl <command>

Commands:
  lock      Lock the session now
  unlock    Drop the lock without a password (trusted callers only)
  status    Print "locked" or "unlocked"
""";

private static LockProxy? connect_proxy() {
    DBusConnection conn;
    try {
        conn = Bus.get_sync(BusType.SESSION);
    } catch (Error e) {
        stderr.printf("lumen-lockctl: session bus unavailable: %s\n", e.message);
        return null;
    }

    if (!LumenCommon.DbusCli.name_has_owner(conn, "org.lumenshell.Lock")) {
        stderr.printf("lumen-lockctl: lumen-lockscreen daemon is not running\n");
        return null;
    }

    try {
        LockProxy proxy = Bus.get_proxy_sync(
            BusType.SESSION, "org.lumenshell.Lock", "/org/lumenshell/Lock",
            DBusProxyFlags.DO_NOT_LOAD_PROPERTIES | DBusProxyFlags.DO_NOT_AUTO_START);
        ((DBusProxy) proxy).set_default_timeout(1500);
        return proxy;
    } catch (Error e) {
        stderr.printf("lumen-lockctl: D-Bus proxy failed: %s\n", e.message);
        return null;
    }
}

public static int main(string[] args) {
    if (args.length < 2) { stderr.printf(USAGE); return 1; }

    switch (args[1]) {
        case "lock":
            var p = connect_proxy();
            if (p == null) return 1;
            try { ((!) p).Lock(); } catch (Error e) {
                stderr.printf("lumen-lockctl: %s\n", e.message); return 1;
            }
            return 0;

        case "unlock":
            var p = connect_proxy();
            if (p == null) return 1;
            try { ((!) p).Unlock(); } catch (Error e) {
                stderr.printf("lumen-lockctl: %s\n", e.message); return 1;
            }
            return 0;

        case "status":
            var p = connect_proxy();
            if (p == null) return 1;
            try {
                stdout.printf("%s\n", ((!) p).IsLocked() ? "locked" : "unlocked");
            } catch (Error e) {
                stderr.printf("lumen-lockctl: %s\n", e.message); return 1;
            }
            return 0;

        case "--help":
        case "-h":
            print(USAGE);
            return 0;

        default:
            stderr.printf(USAGE);
            return 1;
    }
}
