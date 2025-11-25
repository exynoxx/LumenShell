using GLib;
using Gee;

public class IconUtils {
    public static string? find_icon_theme_base(string theme_name) {
        foreach (var base_dir in SystemUtils.get_icon_theme_dirs()) {
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

    public static HashMap<string, string> find_icon_paths(string theme_name, int size = 48) {
        var result = new HashMap<string, string>();
        
        // Find theme base directory
        string? theme_base = find_icon_theme_base(theme_name);
        if (theme_base == null) {
            return result;
        }
        
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
        
        // Icon file extensions
        string[] extensions = { ".png", ".svg", ".jpg", ".jpeg" };
        
        foreach (var size_dir in size_variants) {
            foreach (var category in categories) {
                string dir_path = Path.build_filename(theme_base, size_dir, category);
                
                if (!FileUtils.test(dir_path, FileTest.IS_DIR)) {
                    continue;
                }
                
                try {
                    var directory = Dir.open(dir_path);
                    string? filename;
                    
                    while ((filename = directory.read_name()) != null) {
                        // Check if file has a valid icon extension
                        foreach (var ext in extensions) {
                            if (filename.has_suffix(ext)) {
                                // Extract icon name without extension
                                string icon_name = filename.substring(0, filename.length - ext.length);
                                
                                // Only add if not already found (prefer earlier size variants)
                                if (!result.has_key(icon_name)) {
                                    string full_path = Path.build_filename(dir_path, filename);
                                    result[icon_name] = full_path;
                                }
                                break;
                            }
                        }
                    }
                } catch (FileError e) {
                    // Skip directories we can't read
                    continue;
                }
            }
        }
        
        return result;
    }
}