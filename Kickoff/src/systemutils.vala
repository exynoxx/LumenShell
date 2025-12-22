public class SystemUtils {
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

    public static string[] get_icon_theme_dirs() {
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

        var gtk_settings = ConfigUtils.parse(gtk_settings_file, "Settings");
        if( gtk_settings != null && gtk_settings.has_key("gtk-icon-theme-name"))
            return gtk_settings["gtk-icon-theme-name"];
        
        var kde_settings = ConfigUtils.parse(kde_settings_file, "Icons");
        if (kde_settings != null && kde_settings.has_key("Theme"))
            return kde_settings["Theme"];

        return "hicolor";
    }

    public static string[] get_desktop_files() {
        var files = new Gee.ArrayList<string>();
        foreach (var data_dir in get_xdg_data_dirs()) {
            string apps_dir = Path.build_filename(data_dir, "applications");
            try {
                Dir? dir = Dir.open(apps_dir);

                if (dir == null)
                    continue; // skip non-existent dirs

                //print("get_desktop_files trying %s\n", data_dir);

                string? name;
                while ((name = dir.read_name()) != null) {
                    if (!name.has_suffix(".desktop"))
                        continue;

                    string filepath = Path.build_filename(apps_dir, name);
                    files.add(filepath);
                }
            } catch(FileError e){
                continue;
            }
        }

        return files.to_array();
    }

    public static string get_socket_path(string name){
        string xdg_runtime = Environment.get_variable ("XDG_RUNTIME_DIR");
        if (xdg_runtime == null)
            xdg_runtime = "/tmp";
        var socket_path = Path.build_filename(xdg_runtime, name);
        return socket_path;
    }
}