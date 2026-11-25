// FreeBSD-only (meson adds this file and --define=FREEBSD on FreeBSD hosts).
// Thin Vala face over lumen_bsd.c: sysctl(3), kenv(2), procctl(2), backlight(9).
namespace LumenCommon.Bsd {

    [CCode (cheader_filename = "lumen_bsd.h", cname = "lumen_bsd_set_pdeathsig")]
    public extern int set_pdeathsig(int sig);

    [CCode (cheader_filename = "lumen_bsd.h", cname = "lumen_bsd_sysctl_string")]
    public extern string? sysctl_string(string name);

    [CCode (cheader_filename = "lumen_bsd.h", cname = "lumen_bsd_sysctl_int64")]
    public extern int64 sysctl_int64(string name, int64 def);

    [CCode (cheader_filename = "lumen_bsd.h", cname = "lumen_bsd_uptime_seconds")]
    public extern int64 uptime_seconds();

    [CCode (cheader_filename = "lumen_bsd.h", cname = "lumen_bsd_kenv")]
    public extern string? kenv(string name);

    [CCode (cheader_filename = "lumen_bsd.h", cname = "lumen_bsd_backlight_get")]
    private extern int backlight_get(string device);

    [CCode (cheader_filename = "lumen_bsd.h", cname = "lumen_bsd_backlight_type")]
    private extern int backlight_type(string device);

    [CCode (cheader_filename = "lumen_bsd.h", cname = "lumen_bsd_backlight_set")]
    private extern int backlight_set(string device, int percent);

    // backlight(9) panels: /dev/backlight/backlightN, plus a per-driver alias
    // (intel_backlight0, …) for the same unit. Brightness is always 0..100,
    // so callers treat max as 100. The devices are root:video 0660, so the
    // user must be in the `video` group (scripts/freebsd/setup-system.sh).
    public class Backlight {
        public const string DIR = "/dev/backlight";

        public const int PANEL    = 0;
        public const int KEYBOARD = 1;

        // Lowest backlightN unit of the given BACKLIGHTGETINFO type (panel by
        // default), or null on desktops/VMs. A unit that can't report its
        // type is taken as a panel, the only kind older drivers register.
        public static string? first_device(int type = PANEL) {
            try {
                var dir = Dir.open(DIR);
                string? name;
                string? best = null;
                while ((name = dir.read_name()) != null) {
                    if (!((!) name).has_prefix("backlight")) continue;
                    var path = DIR + "/" + (!) name;
                    int t = backlight_type(path);
                    if (t != type && !(t < 0 && type == PANEL)) continue;
                    if (best == null || strcmp(path, (!) best) < 0) best = path;
                }
                return best;
            } catch (FileError e) {
                return null;
            }
        }

        public static string? keyboard_device() {
            return first_device(KEYBOARD);
        }

        // Accepts a full path or a bare unit name ("backlight0").
        public static string resolve(string device) {
            return device.has_prefix("/") ? device : DIR + "/" + device;
        }

        public static int get_percent(string device) {
            return backlight_get(resolve(device));
        }

        // Falls back to backlight(8), which reports the permission problem
        // on stderr, if the direct ioctl is refused.
        public static bool set_percent(string device, int pct) {
            pct = pct.clamp(0, 100);
            if (backlight_set(resolve(device), pct) == 0) return true;
            LumenCommon.Proc.run_capture(new string[] {
                "backlight", "-f", resolve(device), "%d".printf(pct)
            });
            return get_percent(device) == pct;
        }
    }

    // sysctl(8)-free system facts for lumen-settings' About page.
    public class SysInfo {
        public static string kernel() {
            var type = sysctl_string("kern.ostype") ?? "FreeBSD";
            var rel  = sysctl_string("kern.osrelease");
            return rel != null ? type + " " + (!) rel : type;
        }

        public static string host() {
            var maker   = kenv("smbios.system.maker") ?? "";
            var product = kenv("smbios.system.product") ?? "";
            return (maker + " " + product).strip();
        }

        public static string cpu_model() {
            return sysctl_string("hw.model") ?? "Unknown";
        }

        // Free + inactive + laundry pages count as available, as top(1) does.
        public static void memory(out int64 total_bytes, out int64 avail_bytes) {
            int64 page = sysctl_int64("hw.pagesize", 4096);
            total_bytes = sysctl_int64("hw.physmem", -1);
            int64 free_p = sysctl_int64("vm.stats.vm.v_free_count", -1);
            int64 inact  = sysctl_int64("vm.stats.vm.v_inactive_count", 0);
            int64 laund  = sysctl_int64("vm.stats.vm.v_laundry_count", 0);
            avail_bytes = free_p < 0 ? -1 : (free_p + inact + laund) * page;
        }

        // `pciconf -lv` works unprivileged; display-class devices only.
        public static string[] gpus() {
            string[] found = {};
            string vendor = "", device = "";
            bool display = false;
            var out_s = LumenCommon.Proc.run_capture({ "pciconf", "-lv" }) ?? "";
            foreach (var raw in (out_s + "\nend@").split("\n")) {
                if (raw.length > 0 && !raw[0].isspace()) {
                    if (display) {
                        var s = (vendor + " " + device).strip();
                        if (s != "") found += s;
                    }
                    vendor = ""; device = ""; display = false;
                    continue;
                }
                var line = raw.strip();
                int eq = line.index_of_char('=');
                if (eq < 0) continue;
                var key = line.substring(0, eq).strip();
                var val = line.substring(eq + 1).strip();
                if (val.length >= 2 && val[0] == '\'') val = val.substring(1, val.length - 2);
                if (key == "vendor") vendor = val;
                else if (key == "device") device = val;
                else if (key == "class" && val == "display") display = true;
            }
            return found;
        }
    }
}
