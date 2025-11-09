using GLib;

public class Utils {
    
    // Get XDG data directories
    private static string[] get_xdg_data_dirs() {
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
    
    // Find desktop file from app_id
    public static string? find_desktop_file(string app_id) {
        string[] search_dirs = get_xdg_data_dirs();
        
        // Try exact match first: app_id.desktop
        foreach (string data_dir in search_dirs) {
            string desktop_path = Path.build_filename(data_dir, "applications", app_id + ".desktop");
            if (FileUtils.test(desktop_path, FileTest.EXISTS)) {
                return desktop_path;
            }
        }
        
        // Try case-insensitive match
        foreach (string data_dir in search_dirs) {
            string apps_dir = Path.build_filename(data_dir, "applications");
            try {
                var dir = Dir.open(apps_dir);
                string? name = null;
                while ((name = dir.read_name()) != null) {
                    if (name.down().has_prefix(app_id.down()) && name.has_suffix(".desktop")) {
                        return Path.build_filename(apps_dir, name);
                    }
                }
            } catch (FileError e) {
                // Directory doesn't exist, continue
            }
        }
        
        return null;
    }
    
    // Parse desktop file and get icon name/path
    public static string? get_icon_from_desktop_file(string desktop_file_path) {
        try {
            var key_file = new KeyFile();
            key_file.load_from_file(desktop_file_path, KeyFileFlags.NONE);
            
            if (key_file.has_key("Desktop Entry", "Icon")) {
                return key_file.get_string("Desktop Entry", "Icon");
            }
        } catch (Error e) {
            warning("Failed to parse desktop file: %s", e.message);
        }
        
        return null;
    }
    
    // Get XDG icon theme directories
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
    
    // Find icon file from icon name
    public static string? find_icon_path(string icon_name, int size = 48, string theme = "hicolor") {
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
                "scalable",
                "48x48",
                "32x32",
                "24x24",
                "16x16"
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
    
    // Main function: get icon path from app_id
    public static string? get_icon_path_from_app_id(string app_id, int size = 48) {
        // Find desktop file
        string? desktop_file = find_desktop_file(app_id);
        if (desktop_file == null) {
            warning("Desktop file not found for app_id: %s", app_id);
            return null;
        }
        
        print("Found desktop file: %s\n", desktop_file);
        
        // Get icon name from desktop file
        string? icon_name = get_icon_from_desktop_file(desktop_file);
        if (icon_name == null) {
            warning("No icon specified in desktop file");
            return null;
        }
        
        print("Icon name: %s\n", icon_name);
        
        // Find actual icon file
        string? icon_path = find_icon_path(icon_name, size);
        if (icon_path == null) {
            warning("Icon file not found: %s", icon_name);
            return null;
        }
        
        return icon_path;
    }
}