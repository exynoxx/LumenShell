using GLib;

/**
 * Power profile selectable from the battery page. UNKNOWN means the active
 * backend couldn't report a current value (e.g. tlp-stat needs root) — the UI
 * just highlights nothing in that case.
 */
public enum PowerProfile { UNKNOWN, PERFORMANCE, BALANCED, POWER_SAVER }

/** Which system power manager the panel talks to. NONE hides the selector. */
public enum PowerBackend { NONE, PPD, TLP }

/**
 * power-profiles-daemon is preferred (driven over its system-bus D-Bus
 * interface, no password via polkit, the cross-desktop standard used by Plasma
 * and GNOME alike, and by Fedora's tuned-ppd). TLP is the fallback; its mode
 * commands need root, so writes go through pkexec.
 *
 * The PPD properties are read straight off the cached GVariant rather than via
 * a typed [DBus] interface: ActiveProfile is a plain string, but Profiles is
 * aa{sv} whose values are *boxed* variants — Variant.lookup_value unwraps the
 * box for us, which a typed `HashTable<string,Variant>[]` binding does not.
 *
 * Pure verbs, no stored state — PowerProfileService owns the state.
 */
public class PowerProfileClient : GLib.Object {

    private DBusProxy? ppd = null;
    private bool       ppd_tried = false;

    /**
     * Resolve the backend once. PPD wins when its daemon answers on the system
     * bus; PPD and TLP are mutually exclusive in practice, so a live PPD means
     * TLP isn't the active manager.
     */
    public PowerBackend detect_backend() {
        if (ensure_ppd() != null)
            return PowerBackend.PPD;

        if (Environment.find_program_in_path("tlp") != null
            || Environment.find_program_in_path("tlp-stat") != null)
            return PowerBackend.TLP;

        return PowerBackend.NONE;
    }

    /** Profiles the backend supports, ordered Performance → Balanced → Power Saver. */
    public PowerProfile[] available(PowerBackend backend) {
        if (backend == PowerBackend.TLP)
            return { PowerProfile.PERFORMANCE, PowerProfile.POWER_SAVER };

        if (backend == PowerBackend.PPD) {
            var listed = ppd_list_profiles();
            PowerProfile[] result = {};
            // Fixed display order, filtered by what PPD actually reports.
            foreach (var p in new PowerProfile[] {
                PowerProfile.PERFORMANCE, PowerProfile.BALANCED, PowerProfile.POWER_SAVER }) {
                if (p in listed) result += p;
            }
            // A live PPD always has at least balanced + power-saver; fall back to
            // those two only if the property couldn't be read at all.
            if (result.length == 0)
                result = { PowerProfile.BALANCED, PowerProfile.POWER_SAVER };
            return result;
        }

        return {};
    }

    /** Currently active profile, or UNKNOWN if it can't be determined. */
    public PowerProfile current(PowerBackend backend) {
        if (backend == PowerBackend.PPD) {
            var name = ppd_active_profile();
            return name != "" ? ppd_name_to_profile(name) : PowerProfile.UNKNOWN;
        }

        if (backend == PowerBackend.TLP) {
            // tlp-stat -s prints a "Mode = AC | battery" line. Some of its output
            // needs root, but the Mode line is usually readable as the user.
            var out_str = run_cmd_sync("env LC_ALL=C tlp-stat -s").down();
            foreach (var line in out_str.split("\n")) {
                var l = line.strip();
                if (!l.has_prefix("mode")) continue;
                if (l.contains("battery")) return PowerProfile.POWER_SAVER;
                if (l.contains("ac"))      return PowerProfile.PERFORMANCE;
            }
        }

        return PowerProfile.UNKNOWN;
    }

    /** Apply a profile. No-op for UNKNOWN / NONE. */
    public void set(PowerBackend backend, PowerProfile profile) {
        if (backend == PowerBackend.PPD) {
            string name = profile_to_ppd_name(profile);
            var p = ensure_ppd();
            if (p == null || name == "") return;
            // org.freedesktop.DBus.Properties.Set(iface, "ActiveProfile", <s>).
            // polkit allows this for the active session without a prompt. Errors
            // are swallowed (the next poll reflects the real state) like the
            // other fire-and-forget verbs.
            try {
                p.call_sync(
                    "org.freedesktop.DBus.Properties.Set",
                    new Variant("(ssv)", p.get_interface_name(),
                                "ActiveProfile", new Variant.string(name)),
                    DBusCallFlags.NONE, 2000, null);
            } catch (Error e) {}
            return;
        }

        if (backend == PowerBackend.TLP) {
            // tlp ac/bat need root — pkexec raises a polkit auth dialog.
            string mode = profile == PowerProfile.PERFORMANCE ? "ac" : "bat";
            LumenCommon.Proc.spawn_detached(new string[] { "pkexec", "tlp", mode });
        }
    }

    // --- PPD helpers ---

    // Cache one proxy for the lifetime of the client. GDBusProxy keeps the
    // ActiveProfile cache fresh via PropertiesChanged, so later reads stay live.
    private DBusProxy? ensure_ppd() {
        if (ppd_tried) return ppd;
        ppd_tried = true;
        // Newer power-profiles-daemon renamed the service; try it first, then
        // fall back to the legacy name still owned for compatibility (and the
        // only name tuned-ppd exposes).
        ppd = try_ppd("org.freedesktop.UPower.PowerProfiles",
                      "/org/freedesktop/UPower/PowerProfiles")
           ?? try_ppd("net.hadess.PowerProfiles",
                      "/net/hadess/PowerProfiles");
        return ppd;
    }

    private DBusProxy? try_ppd(string name, string path) {
        try {
            var p = new DBusProxy.for_bus_sync(
                BusType.SYSTEM, DBusProxyFlags.DO_NOT_AUTO_START, null,
                name, path, name, null);
            // No owner → no cached props; treat as "not this name".
            var ap = p.get_cached_property("ActiveProfile");
            if (ap != null && ap.is_of_type(VariantType.STRING)
                && ap.get_string() != "")
                return p;
        } catch (Error e) {}
        return null;
    }

    private string ppd_active_profile() {
        var p = ensure_ppd();
        if (p == null) return "";
        var ap = p.get_cached_property("ActiveProfile");
        return (ap != null && ap.is_of_type(VariantType.STRING)) ? ap.get_string() : "";
    }

    private PowerProfile[] ppd_list_profiles() {
        PowerProfile[] found = {};
        var p = ensure_ppd();
        if (p == null) return found;

        var raw = p.get_cached_property("Profiles"); // aa{sv}
        if (raw == null) return found;

        for (size_t i = 0; i < raw.n_children(); i++) {
            var dict = raw.get_child_value(i); // a{sv}
            // lookup_value unwraps the boxed 'v' value automatically.
            var val = dict.lookup_value("Profile", VariantType.STRING);
            if (val == null) continue;
            var prof = ppd_name_to_profile(val.get_string());
            if (prof != PowerProfile.UNKNOWN && !(prof in found)) found += prof;
        }
        return found;
    }

    private PowerProfile ppd_name_to_profile(string name) {
        switch (name.down()) {
            case "performance": return PowerProfile.PERFORMANCE;
            case "balanced":    return PowerProfile.BALANCED;
            case "power-saver": return PowerProfile.POWER_SAVER;
            default:            return PowerProfile.UNKNOWN;
        }
    }

    private string profile_to_ppd_name(PowerProfile p) {
        switch (p) {
            case PowerProfile.PERFORMANCE: return "performance";
            case PowerProfile.BALANCED:    return "balanced";
            case PowerProfile.POWER_SAVER: return "power-saver";
            default:                       return "";
        }
    }

    private string run_cmd_sync(string cmd) {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(cmd, out out_str, null, null);
        } catch (SpawnError e) {
            return "";
        }
        return out_str;
    }
}
