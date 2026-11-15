using LumenCommon;

// Baked in by lumen-settings/meson.build from meson.project_version().
[CCode (cname = "LUMEN_VERSION")]
extern const string LUMEN_VERSION;

namespace LumenSettings {

    // neofetch-style system summary. Pages are built eagerly at startup, so
    // values are (re)read on map — uptime/memory stay current — and the two
    // subprocess probes (lspci, wayfire --version) run once on a thread.
    public class AboutPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "about"; } }
        public string title     { owned get { return "About"; } }
        public string icon_name { owned get { return "lumen-settings-about"; } }

        HashTable<string, Adw.ActionRow> rows = new HashTable<string, Adw.ActionRow>(str_hash, str_equal);
        bool probed = false;

        public Gtk.Widget build() {
            var os = read_os_release();
            var page = new Adw.PreferencesPage();

            var head = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
                halign = Gtk.Align.CENTER, margin_bottom = 12,
            };
            var logo_name = os["LOGO"] ?? "";
            var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
            head.append(new Gtk.Image.from_icon_name(
                logo_name != "" && theme.has_icon(logo_name) ? logo_name : "computer") {
                pixel_size = 128,
            });
            var heading = new Gtk.Label(os["PRETTY_NAME"] ?? os["NAME"] ?? "Linux") {
                selectable = true,
            };
            heading.add_css_class("lumen-about-title");
            head.append(heading);
            var head_group = new Adw.PreferencesGroup();
            head_group.add(head);
            page.add(head_group);

            var sys = new Adw.PreferencesGroup() { title = "System" };
            foreach (var k in new string[] { "OS", "Kernel", "Host", "Hostname", "Uptime" })
                sys.add(make_row(k));
            page.add(sys);

            var hw = new Adw.PreferencesGroup() { title = "Hardware" };
            foreach (var k in new string[] { "CPU", "GPU", "Memory", "Disk (/)", "Display" })
                hw.add(make_row(k));
            page.add(hw);

            var sess = new Adw.PreferencesGroup() { title = "Session" };
            foreach (var k in new string[] { "Shell", "Compositor", "Desktop", "LumenShell" })
                sess.add(make_row(k));
            page.add(sess);

            set("OS", os["PRETTY_NAME"] ?? "Unknown");
            set("LumenShell", LUMEN_VERSION);
            set("Hostname", Environment.get_host_name());
            set("Desktop", Environment.get_variable("XDG_CURRENT_DESKTOP") ?? "Unknown");
            var shell = Environment.get_variable("SHELL");
            set("Shell", shell != null ? Path.get_basename(shell) : "Unknown");

            page.map.connect(refresh);
            return page;
        }

        Adw.ActionRow make_row(string key) {
            var row = new Adw.ActionRow() {
                title = key, subtitle = "…", use_markup = false, subtitle_selectable = true,
            };
            row.add_css_class("property");
            rows[key] = row;
            return row;
        }

        new void set(string key, string value) {
            rows[key].subtitle = value;
        }

        void refresh() {
            set("Kernel", read_line("/proc/sys/kernel/osrelease") ?? "Unknown");
            var vendor = read_line("/sys/class/dmi/id/sys_vendor") ?? "";
            var product = read_line("/sys/class/dmi/id/product_name") ?? "";
            set("Host", (vendor + " " + product).strip() != "" ? (vendor + " " + product).strip() : "Unknown");
            set("Uptime", uptime());
            set("CPU", cpu());
            set("Memory", memory());
            set("Disk (/)", disk());
            set("Display", displays());

            if (probed) return;
            probed = true;
            new Thread<void*>("about-probe", () => {
                var gpu = gpu();
                var wf = Proc.run_capture({ "wayfire", "--version" });
                string comp = "Wayfire";
                if (wf != null && wf.strip() != "") comp = "Wayfire " + wf.strip().split(" ")[0];
                Idle.add(() => {
                    set("GPU", gpu);
                    set("Compositor", comp);
                    return Source.REMOVE;
                });
                return null;
            });
        }

        static string? read_line(string path) {
            try {
                string s;
                FileUtils.get_contents(path, out s);
                return s.strip();
            } catch (Error e) {
                return null;
            }
        }

        static HashTable<string, string> read_os_release() {
            var t = new HashTable<string, string>(str_hash, str_equal);
            var s = read_line("/etc/os-release") ?? read_line("/usr/lib/os-release") ?? "";
            foreach (var line in s.split("\n")) {
                var eq = line.index_of_char('=');
                if (eq <= 0) continue;
                var v = line.substring(eq + 1).strip();
                if (v.length >= 2 && (v[0] == '"' || v[0] == '\''))
                    v = v.substring(1, v.length - 2);
                t[line.substring(0, eq).strip()] = v;
            }
            return t;
        }

        static string uptime() {
            var s = read_line("/proc/uptime");
            if (s == null) return "Unknown";
            var secs = (int64) double.parse(s.split(" ")[0]);
            int d = (int) (secs / 86400), h = (int) (secs % 86400 / 3600), m = (int) (secs % 3600 / 60);
            if (d > 0) return "%dd %dh %dm".printf(d, h, m);
            if (h > 0) return "%dh %dm".printf(h, m);
            return "%dm".printf(m);
        }

        static string cpu() {
            var model = "Unknown";
            foreach (var line in (read_line("/proc/cpuinfo") ?? "").split("\n")) {
                if (line.has_prefix("model name")) {
                    model = line.substring(line.index_of_char(':') + 1).strip();
                    break;
                }
            }
            return "%s (%u threads)".printf(model, get_num_processors());
        }

        static string memory() {
            int64 total = -1, avail = -1;
            foreach (var line in (read_line("/proc/meminfo") ?? "").split("\n")) {
                var parts = line.split_set(": ", 0);
                string[] f = {};
                foreach (var p in parts) if (p != "") f += p;
                if (f.length < 2) continue;
                if (f[0] == "MemTotal") total = int64.parse(f[1]);
                else if (f[0] == "MemAvailable") avail = int64.parse(f[1]);
            }
            if (total < 0 || avail < 0) return "Unknown";
            return "%s / %s".printf(format_size((uint64) (total - avail) * 1024),
                                    format_size((uint64) total * 1024));
        }

        static string disk() {
            try {
                var info = File.new_for_path("/").query_filesystem_info("filesystem::size,filesystem::free");
                var size = info.get_attribute_uint64(FileAttribute.FILESYSTEM_SIZE);
                var free = info.get_attribute_uint64(FileAttribute.FILESYSTEM_FREE);
                return "%s / %s".printf(format_size(size - free), format_size(size));
            } catch (Error e) {
                return "Unknown";
            }
        }

        static string displays() {
            string[] out_s = {};
            var mons = Gdk.Display.get_default().get_monitors();
            for (uint i = 0; i < mons.get_n_items(); i++) {
                var m = (Gdk.Monitor) mons.get_item(i);
                var g = m.geometry;
                out_s += "%s %d×%d @ %d Hz".printf(
                    m.connector ?? "?",
                    (int) Math.round(g.width * m.scale), (int) Math.round(g.height * m.scale),
                    (int) Math.round(m.refresh_rate / 1000.0));
            }
            return out_s.length > 0 ? string.joinv(", ", out_s) : "Unknown";
        }

        static string gpu() {
            var lspci = Proc.run_capture({ "lspci" });
            string[] gpus = {};
            foreach (var line in (lspci ?? "").split("\n")) {
                if (!("VGA compatible controller" in line || "3D controller" in line
                      || "Display controller" in line)) continue;
                var parts = line.split(": ", 2);
                if (parts.length == 2) gpus += parts[1].strip();
            }
            return gpus.length > 0 ? string.joinv("\n", gpus) : "Unknown";
        }
    }
}
