// UNKNOWN: the backend couldn't report a value (e.g. tlp-stat needs root).
public enum PowerProfile { UNKNOWN, PERFORMANCE, BALANCED, POWER_SAVER }

public enum PowerBackend { NONE, PPD, TLP }

// power-profiles-daemon is preferred (polkit, no prompt); TLP is the fallback and
// its mode commands need root, so writes go through pkexec.
public class PowerProfileClient : GLib.Object {

    private DBusProxy? ppd = null;
    private bool       ppd_tried = false;

    // PPD only: its PropertiesChanged arrived (ActiveProfile/Profiles changed).
    public signal void changed();

    // PPD and TLP are mutually exclusive in practice, so a live PPD wins.
    public PowerBackend detect_backend() {
        if (ensure_ppd() != null)
            return PowerBackend.PPD;

        if (Environment.find_program_in_path("tlp") != null
            || Environment.find_program_in_path("tlp-stat") != null)
            return PowerBackend.TLP;

        return PowerBackend.NONE;
    }

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

    public PowerProfile current(PowerBackend backend) {
        if (backend == PowerBackend.PPD) {
            var name = ppd_active_profile();
            return name != "" ? ppd_name_to_profile(name) : PowerProfile.UNKNOWN;
        }

        if (backend == PowerBackend.TLP) {
            // tlp-stat -s prints a "Mode = AC | battery" line. Some of its output
            // needs root, but the Mode line is usually readable as the user.
            var out_str = (LumenCommon.Proc.run_capture(
                new string[] { "tlp-stat", "-s" },
                new string[] { "LC_ALL=C" }) ?? "").down();
            foreach (var line in out_str.split("\n")) {
                var l = line.strip();
                if (!l.has_prefix("mode")) continue;
                if (l.contains("battery")) return PowerProfile.POWER_SAVER;
                if (l.contains("ac"))      return PowerProfile.PERFORMANCE;
            }
        }

        return PowerProfile.UNKNOWN;
    }

    public void set(PowerBackend backend, PowerProfile profile) {
        if (backend == PowerBackend.PPD) {
            string name = profile_to_ppd_name(profile);
            var p = ensure_ppd();
            if (p == null || name == "") return;
            // polkit allows this for the active session without a prompt; async and
            // errors swallowed (the next poll shows the real state).
            p.call.begin(
                "org.freedesktop.DBus.Properties.Set",
                new Variant("(ssv)", p.get_interface_name(),
                            "ActiveProfile", new Variant.string(name)),
                DBusCallFlags.NONE, 2000, null, (obj, res) => {
                    try { p.call.end(res); } catch (Error e) {}
                });
            return;
        }

        if (backend == PowerBackend.TLP) {
            // tlp ac/bat need root — pkexec raises a polkit auth dialog.
            string mode = profile == PowerProfile.PERFORMANCE ? "ac" : "bat";
            LumenCommon.Proc.spawn_detached(new string[] { "pkexec", "tlp", mode });
        }
    }

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
        if (ppd != null) ppd.g_properties_changed.connect(() => changed());
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
            // lookup_value unwraps the boxed 'v'; a typed [DBus] binding would not.
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
}
