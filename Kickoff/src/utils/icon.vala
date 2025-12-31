using GLib;
using Gee;

namespace Utils {

    public class Icon {

        public static HashSet<string> extensions;

        public static HashMap<string, string> load_or_create_icon_cache(int size) {
            print("loading icon paths\n");
            
            var location = Path.build_filename(Environment.get_user_data_dir(), "Kickoff", "icons.cache");
            
            var map = Utils.Serialization.load_from_file(location);
            if(map == null){
                print("icon cache not found. Creating.\n");
                map = find_all_icon_paths(size);
                Utils.Serialization.save_to_file(map, location);

                //test
                var testmap = Utils.Serialization.load_from_file(location);
                foreach(var k in map.keys){
                    if(!testmap.has_key(k)){
                        print("mismatch k %s\n", k);
                        WLHooks.destroy();
                        Process.exit (0);
                    }
                }
            }

            return map;
        }

        public static HashMap<string, string> find_all_icon_paths(int size){

            if(extensions == null){
                extensions = new HashSet<string>();
                extensions.add("png");
                extensions.add("svg");
                extensions.add("jpg");
                extensions.add("jpeg");
            }

            var icon_theme = Utils.System.get_current_theme();
            print("using icon theme: %s\n", icon_theme);

            var icon_theme_base = find_icon_theme_base(icon_theme);
            var theme_icon_paths = find_theme_icons(icon_theme_base, size);

            var exclude = new HashSet<string>();
            exclude.add(icon_theme_base);
            foreach(var dir in Utils.System.get_data_dir("Trash")){
                exclude.add(dir);
            }
            foreach(var dir in Utils.System.get_data_dir("icons")){
                exclude.add(dir);
            }

            foreach(var dir in Utils.System.get_data_dirs()){
                all_icons_in_subtree (dir, exclude, theme_icon_paths);
            }

            return theme_icon_paths;
        }

        public static string? find_icon_theme_base(string theme_name) {
            foreach (var base_dir in System.get_data_dir("icons")) {
                string theme_dir = Path.build_filename(base_dir, theme_name);
        
                // Check if directory exists and has index.theme
                if (FileUtils.test(theme_dir, FileTest.IS_DIR)) {
                    string index_file = Path.build_filename(theme_dir, "index.theme");
                    if (FileUtils.test(index_file, FileTest.EXISTS)) {
                        return theme_dir;
                    }
                }
            }
        
            // Theme not found
            return null;
        }
    
        public static HashMap<string, string> find_theme_icons(string theme_base, int size) {
            var result = new HashMap<string, string>();

            // Common size directories to check
            string[] size_variants = {
                @"$(size)x$(size)",
                @"$(size)x$(size)@2x",
                "scalable"
            };
            
            // Common subdirectories where icons are found
            string[] categories = {
                "apps",
                "applications",
                "actions",
                "places",
                "panel",
                "mimetypes",
                "devices",
                "categories",
                "emblems",
                "status"
            };
            
            foreach (var size_dir in size_variants) {
                foreach (var category in categories) {
                    string dir_path = Path.build_filename(theme_base, size_dir, category);
                    
                    if (!FileUtils.test(dir_path, FileTest.IS_DIR)) {
                        continue;
                    }

                    System.enumerate_dir_action(dir_path, filename=>add_if_icon(dir_path, filename, result));
                }
            }
            
            return result;
        }

        public static void all_icons_in_subtree(string current_path, HashSet<string> exclude, HashMap<string, string> result ) {
            if(exclude.contains(current_path)) 
                return;

            try {
                var directory = Dir.open(current_path);
                string? filename;
                
                while ((filename = directory.read_name()) != null) {

                    var path = Path.build_filename(current_path, filename);
                    if (FileUtils.test(path, FileTest.IS_DIR)) {
                        all_icons_in_subtree(path, exclude, result);

                    } else if (FileUtils.test(path, FileTest.IS_REGULAR)){
                        add_if_icon(current_path, filename, result);
                    }
                }
            } catch (FileError e) {
                // Skip directories we can't read
            }
        }

        private static void add_if_icon(string current_path, string filename, HashMap<string, string> result){
            var parts = filename.split (".", 2);
            if (parts.length < 2) 
                return;

            string icon_name = parts[0];
            string ext = parts[1];

            if(!result.has_key(icon_name) && extensions.contains(ext)){
                result[icon_name] = Path.build_filename(current_path, filename);
            }
        }
        
 
    }
}
