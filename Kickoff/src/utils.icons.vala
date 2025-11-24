using GLib;

namespace Utils {

    public class System {
        public static string[] get_xdg_data_dirs() {
            var dirs = new Gee.ArrayList<string>();
            
            // Add user data directory first
            string user_data_dir = Environment.get_user_data_dir();
            dirs.add(user_data_dir);
            
            // Add system data directories
            string system_dirs = Environment.get_variable("XDG_DATA_DIRS");
            if (system_dirs == null || system_dirs == "") {
                system_dirs = "/usr/local/share:/usr/share";
            }
            
            foreach (string dir in system_dirs.split(":")) {
                if (dir != "") {
                    dirs.add(dir);
                }
            }
            
            return dirs.to_array();
        }

        private static string[] get_icon_theme_dirs() {
            var dirs = new Gee.ArrayList<string>();
            
            // User icon directory
            string home = Environment.get_home_dir();
            dirs.add(Path.build_filename(home, ".icons"));
            dirs.add(Path.build_filename(home, ".local", "share", "icons"));
            
            // System icon directories
            string[] data_dirs = get_xdg_data_dirs();
            foreach (string data_dir in data_dirs) {
                dirs.add(Path.build_filename(data_dir, "icons"));
            }
            
            dirs.add("/usr/share/pixmaps");
            
            return dirs.to_array();
        }

        public static string get_current_theme() {
            var gtk_settings_file = Environment.get_home_dir() + "/.config/gtk-4.0/settings.ini";
            var kde_settings_file = Environment.get_home_dir() + "/.config/kdeglobals";
    
            var gtk_settings = Utils.Config.parse(gtk_settings_file, "Settings");
            if( gtk_settings != null && gtk_settings.has_key("gtk-icon-theme-name"))
                return gtk_settings["gtk-icon-theme-name"];
            
            var kde_settings = Utils.Config.parse(kde_settings_file, "Icons");
            if (kde_settings != null && kde_settings.has_key("Theme"))
                return kde_settings["Theme"];

            return "hicolor";
        }

        public iterator<string> load_desktop_files() {
            foreach (var data_dir in get_xdg_data_dirs()) {
                string apps_dir = Path.build_filename(data_dir, "applications");
                Dir? dir = Dir.open(apps_dir);

                if (dir == null)
                    continue; // skip non-existent dirs

                string? name;
                while ((name = dir.read_name()) != null) {
                    if (!name.has_suffix(".desktop"))
                        continue;

                    string filepath = Path.build_filename(apps_dir, name);
                    yield filepath; //TODO not possible
                }
            }
        }
    }

    public class Find {
        public static string? find_icon_theme_base(string theme_name) {
            foreach (var base_dir in System.get_icon_theme_dirs()) {
                string theme_dir = Path.build_filename(base_dir, theme_name);
        
                // Check if directory exists and has index.theme
                if (File.test(theme_dir, FileTest.IS_DIR)) {
                    string index_file = Path.build_filename(theme_dir, "index.theme");
                    if (File.test(index_file, FileTest.EXISTS)) {
                        return theme_dir;
                    }
                }
            }
        
            // Theme not found
            return null;
        }

        public static string? lookup_icon(string icon_name, string theme_name, int size = 48) {
            var dirs = get_icon_dirs();
            var contexts = { "apps", "actions", "devices", "places" };
            var exts = { ".png", ".svg", ".xpm" };
    
            foreach (var base_dir in dirs) {
                string theme_dir = Path.build_filename(base_dir, theme_name);
                if (!File.test(theme_dir, FileTest.IS_DIR))
                    continue;
    
                foreach (var context in contexts) {
                    string size_dir = Path.build_filename(theme_dir, "%dx%d".printf(size, size), context);
                    if (File.test(size_dir, FileTest.IS_DIR)) {
                        foreach (var ext in exts) {
                            string candidate = Path.build_filename(size_dir, icon_name + ext);
                            if (File.test(candidate, FileTest.EXISTS))
                                return candidate;
                        }
                    }
    
                    // scalable icons
                    string scalable_dir = Path.build_filename(theme_dir, "scalable", context);
                    if (File.test(scalable_dir, FileTest.IS_DIR)) {
                        foreach (var ext in exts) {
                            string candidate = Path.build_filename(scalable_dir, icon_name + ext);
                            if (File.test(candidate, FileTest.EXISTS))
                                return candidate;
                        }
                    }
                }
    
                // index.theme Inherits fallback could be parsed here (optional)
            }
    
            // last-resort fallback
            foreach (var ext in exts) {
                string fallback = Path.build_filename("/usr/share/pixmaps", icon_name + ext);
                if (File.test(fallback, FileTest.EXISTS))
                    return fallback;
            }
    
            return null; // icon not found
        }
    }
    }
    
    // Find icon file from icon name
    public static string? find_icon_path(string icon_name, int size = 32) {

        var theme = get_current_icon_theme();

        // If it's already an absolute path, return it
        if (Path.is_absolute(icon_name)) {
            if (FileUtils.test(icon_name, FileTest.EXISTS)) {
                return icon_name;
            }
        }
        
        string[] icon_dirs = get_icon_theme_dirs();
        string[] extensions = { ".png", ".svg", ".xpm" };
        
        // Search in theme directories
        foreach (string icon_dir in icon_dirs) {
            // Try themed icon first
            string[] size_dirs = {
                @"$(size)x$(size)",
                "48x48",
                "32x32",
                "24x24",
                "16x16",
                "scalable",
            };
            
            foreach (string size_dir in size_dirs) {
                foreach (string ext in extensions) {
                    string icon_path = Path.build_filename(
                        icon_dir, 
                        theme, 
                        size_dir, 
                        "apps", 
                        icon_name + ext
                    );
                    if (FileUtils.test(icon_path, FileTest.EXISTS)) {
                        return icon_path;
                    }
                }
            }
            
            // Try without theme subdirectory
            foreach (string ext in extensions) {
                string icon_path = Path.build_filename(icon_dir, icon_name + ext);
                if (FileUtils.test(icon_path, FileTest.EXISTS)) {
                    return icon_path;
                }
            }
        }
        
        return null;
    }
    
}