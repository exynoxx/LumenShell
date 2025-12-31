using Gee;

namespace Utils {
    public class System {
        public static string[]? data_dirs;
        public static string[] get_data_dirs() {

            if(data_dirs != null ) 
                return data_dirs;

            var dirs = new HashSet<string>();
            
            dirs.add(Environment.get_user_data_dir());
            dirs.add("/usr/local/share");
            dirs.add("/usr/share");
            
            string system_dirs = Environment.get_variable("XDG_DATA_DIRS");
            foreach (string dir in system_dirs.split(":")) {
                if (dir != "") {
                    dirs.add(dir);
                }
            }

            data_dirs = dirs.to_array();
            return data_dirs;
        }

        public static HashMap<string,HashSet<string>> data_dir_cache = new HashMap<string,HashSet<string>>();
        public static string[] get_data_dir(string dir) {
            if(data_dir_cache.has_key(dir)) 
                return data_dir_cache[dir].to_array();;

            var dirs = new HashSet<string>();
            foreach (string data_dir in get_data_dirs()) {
                dirs.add(Path.build_filename(data_dir, dir));
            }
            
            data_dir_cache[dir] = dirs;
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

        public static string[] enumerate_dir(string path){
            var files = new Gee.ArrayList<string>();
            try {
                Dir? dir = Dir.open(path);

                if (dir == null)
                    return files.to_array();; // skip non-existent dirs
                string? name;
                while ((name = dir.read_name()) != null) {

                    if (!FileUtils.test(path, FileTest.IS_REGULAR))
                        continue;

                    files.add(Path.build_filename(path, name));
                }
            } catch(FileError e){
                return files.to_array();
            }

            return files.to_array();
        }
    
        public static string[] get_desktop_files() {
            var applications = get_data_dir("applications");

            var files = new Gee.ArrayList<string>();
            foreach(var app_dir in applications){
                foreach (var name in enumerate_dir(app_dir)) {
                    if (name.has_suffix(".desktop"))
                        files.add(name);
                }
            }
            
    
            return files.to_array();
        }
    }
}

