using Gee;

public class ConfigUtils {
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

    public static string? valueOrDefault (HashMap<string, string> lookup, string key, string defaul){
        return lookup.has_key(key) ? lookup[key] : defaul;
    }
}