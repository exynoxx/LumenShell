using Gee;

namespace Utils {

    public class Config {
        public static HashMap<string, string>? parse(string file_path, string section){
            string target = "["+section+"]";
            if (!FileUtils.test(file_path, FileTest.EXISTS))
                return null;
    
            var result = new HashMap<string,string>();
            try {
    
                FileStream stream = FileStream.open (file_path, "r");
                assert (stream != null);
    
                string? line = null;
                bool inside = false;
                while ((line = stream.read_line ()) != null) {
                    string l = line.strip();
    
                    if(l[0] == '[') {
                        if(inside) break;
                        inside = (l == target);
                        continue;
                    }
    
                    if(!l.contains("=")){
                        continue;
                    }
    
                    string[] parts = l.split("=", 2);
                    result[parts[0]] = parts[1];
                }
    
                return result;
            } catch (Error e) {
                warning("Failed to read INI file '%s': %s", file_path, e.message);
            }
            
            return result;
        }

        public static string? valueOrDefault (HashMap<string, string> lookup, string key){
            return lookup.has_key(lookup) ? lookup[key] : null;
        }
    }

    /*  


    private AppEntry? parse_desktop_file(string filepath) {
        var file = File.new_for_path(filepath);
        
        try {
            var stream = new DataInputStream(file.read());
            string line;
            bool in_desktop_entry = false;
            
            AppEntry entry = AppEntry();
            entry.name = "";
            entry.icon_path = "";
            entry.exec = "";
            entry.texture_loaded = false;
            entry.texture_id = 0;
            
            bool no_display = false;
            
            while ((line = stream.read_line()) != null) {
                line = line.strip();
                
                if (line.length == 0 || line[0] == '#') continue;
                
                if (line == "[Desktop Entry]") {
                    in_desktop_entry = true;
                    continue;
                }
                
                if (line[0] == '[' && line != "[Desktop Entry]") {
                    in_desktop_entry = false;
                }
                
                if (!in_desktop_entry) continue;
                
                if (line.has_prefix("Name=")) {
                    entry.name = line.substring(5);
                } else if (line.has_prefix("Icon=")) {
                    entry.icon_path = line.substring(5);
                } else if (line.has_prefix("Exec=")) {
                    entry.exec = line.substring(5);
                } else if (line.has_prefix("NoDisplay=true")) {
                    no_display = true;
                } else if (line.has_prefix("Type=") && line.substring(5) != "Application") {
                    return null;
                }
            }
            
            if (no_display || entry.name == "" || entry.exec == "") {
                return null;
            }
            
            return entry;
            
        } catch (Error e) {
            stderr.printf("Error parsing %s: %s\n", filepath, e.message);
            return null;
        }
    }  */
}