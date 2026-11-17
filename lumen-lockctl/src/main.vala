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

    var cmd = args[1];
    if (cmd == "--help" || cmd == "-h") { print(USAGE); return 0; }
    if (cmd != "lock" && cmd != "unlock" && cmd != "status") { stderr.printf(USAGE); return 1; }

    var p = connect_proxy();
    if (p == null) return 1;
    try {
        switch (cmd) {
            case "lock":   ((!) p).Lock(); break;
            case "unlock": ((!) p).Unlock(); break;
            default:       stdout.printf("%s\n", ((!) p).IsLocked() ? "locked" : "unlocked"); break;
        }
    } catch (Error e) {
        stderr.printf("lumen-lockctl: %s\n", e.message);
        return 1;
    }
    return 0;
}
