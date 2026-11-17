using GLib;

private const string USAGE =
"""Usage: lumen-lockctl <command>

Commands:
  lock      Lock the session now
  unlock    Drop the lock without a password (trusted callers only)
  status    Print "locked" or "unlocked"
""";

private static LockProxy? connect_proxy() {
    return LumenCommon.DbusCli.connect<LockProxy>("lumen-lockctl", "lumen-lockscreen", "org.lumenshell.Lock", "/org/lumenshell/Lock");
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
