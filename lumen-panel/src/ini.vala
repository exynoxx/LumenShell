//gtk-icon-theme-name
using Gee;
using GLib;

public class Ini {
    public static string? Get_key_value(string file_path, string key){
        if (!FileUtils.test(file_path, FileTest.EXISTS))
        return null;

        string? value = null;

        FileStream stream = FileStream.open (file_path, "r");
        assert (stream != null);

        string? line = null;
        while ((line = stream.read_line ()) != null) {
            string l = line.strip();
            if(!l.contains("=")){
                continue;
            }

            string[] parts = l.split("=", 2);
            if (parts[0].strip() == key) {
                value = parts[1].strip();
                break;
            }
        }

        return value;
    }

    public static ArrayList<string> read_lines(string file_path){
        var lines = new ArrayList<string>();
        if (!FileUtils.test(file_path, FileTest.EXISTS)) {
            return lines;
        }

        try {
            string content;
            size_t len;
            FileUtils.get_contents(file_path, out content, out len);
            foreach (var line in content.split("\n")) {
                var trimmed = line.strip();
                if(trimmed != "") lines.add(trimmed);
            }
        } catch (Error e) {
            stderr.printf("Failed reading %s: %s\n", file_path, e.message);
        }

        return lines;
    }

    public static void write_lines(string file_path, Gee.List<string> lines){
        var parent = Path.get_dirname(file_path);
        try {
            DirUtils.create_with_parents(parent, 0755);
        } catch (Error e) {
            stderr.printf("Failed creating dir %s: %s\n", parent, e.message);
            return;
        }

        var sb = new StringBuilder();
        foreach (var line in lines) {
            sb.append(line);
            sb.append("\n");
        }

        try {
            FileUtils.set_contents(file_path, sb.str);
        } catch (Error e) {
            stderr.printf("Failed writing %s: %s\n", file_path, e.message);
        }
    }
}